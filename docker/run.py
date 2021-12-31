import os
import json
from jsonpath_rw_ext import parse
from google.cloud import pubsub_v1


def create_topic(topic_path):
    print(f"creating topic: {topic_path}")
    publisher = pubsub_v1.PublisherClient()
    return publisher.create_topic(request={"name": topic_path})


def create_subscription(topic_path, push_endpoint):
    subscriber = pubsub_v1.SubscriberClient()
    parsed_dict = subscriber.parse_topic_path(topic_path)
    project = parsed_dict.get("project")
    topic = parsed_dict.get("topic")
    subscription_path = subscriber.subscription_path(project, topic)
    subscriber.create_subscription(request={"name": subscription_path, "topic": topic_path, "push_config": {
                                   "push_endpoint": push_endpoint}})


def read_output_value(output_name):
    expression = parse(f'$.outputs."{output_name}"')
    return expression.find(tf_state)[0].value.get("value")


# get the project context currently set in gcloud
project_id = os.popen("gcloud config get-value project").read()


# read the terraform state file
tf_state = json.load(open("/app/terraform.tfstate"))

# start cloud_sql_proxy
master_instance_name = read_output_value("master-db-connection-name")
os.system(
    f"./cloud_sql_proxy -instances={master_instance_name}=tcp:5432 &>/dev/null &")

# start pubsub emulator
os.system(
    f"gcloud --quiet beta emulators pubsub start --project=\"{project_id}\" &")
export_command = os.popen("gcloud beta emulators pubsub env-init").read()
env_var = export_command.split(" ")[1]
env_var_name, env_var_value = env_var.split("=")
os.environ[env_var_name] = env_var_value

# save for later
topic_paths = []

# read the cloud functions triggered by pubsub and create the topics they listen to
expression = parse(
    """$.resources[?type=="google_pubsub_topic"].instances[*].attributes.id""")
for topic_path in {match.value for match in expression.find(tf_state)}:
    create_topic(topic_path)
    topic_paths.append(topic_path)

# read each function, and start each on its own port
port = 8080
nginx_config = ""
for cf_dir in os.scandir("./workspace/src/cloud-functions"):
    dir_name = cf_dir.path.split("/")[-1]
    expression = parse(
        f"""$.resources[?type=="google_cloudfunctions_function"].instances[?attributes.labels.
        directory_name=="{dir_name}"].attributes.environment_variables""")
    env_vars = expression.find(tf_state)[0].value
    # host needs to be set for local function execution
    env_vars["HOST"] = "localhost"

    # read the config file and get the debug port
    config_path = f"{cf_dir.path}/config.json"
    if os.path.exists(config_path):
        with (open(config_path)) as config_file:
            config = json.loads(config_file.read())
        debug_port = config.get("debug-port")
        env_vars["DEBUG_PORT"] = debug_port

    env_vars_formatted = " ".join(
        [f"{key}={value}" for key, value in env_vars.items()])

    # create symlinks to shared modules
    for entry in os.listdir("./workspace/src/shared"):
        if entry == "__pycache__":
            continue
        entry_path = f"{cf_dir.path}/{entry}"
        if os.path.exists(entry_path):
            os.remove(entry_path)
        os.system(f"ln -s ../../shared/{entry} {cf_dir.path}/{entry}")

    # start hosting the function within functions framework; note that it is assumed every function has an "entry_point" function
    ff_command = f"""{env_vars_formatted} functions-framework --port {port} --source ./{cf_dir.path}/main.py --target entry_point &>/dev/null &"""
    os.system(ff_command)
    print(f"started function '{dir_name}' and debugging on {debug_port}")

    # for functions subscribing to topics, create subscription
    expression = parse(
        f"""$.resources[?type=="google_cloudfunctions_function"].instances[?attributes.labels.
        directory_name=="{dir_name}"].attributes.event_trigger[?event_type="providers/cloud.pubsub/eventTypes/topic.publish"].resource""")
    matches = expression.find(tf_state)
    if len(matches):
        resource_name = matches[0].value
        # resolve the resource name to the full topic path
        topic_path = [
            topic_path for topic_path in topic_paths if resource_name in topic_path][0]
        create_subscription(topic_path, f"http://localhost:{port}")

    # append any nginx config snippets to the nginx config string
    nginx_file_path = f"{cf_dir.path}/nginx"
    if os.path.exists(nginx_file_path):
        with open(nginx_file_path) as file:
            contents = file.read().replace("$URL", f"http://localhost:{port}")
            nginx_config = f"{nginx_config}\t{contents}\n"

    # each function is individually hosted, and thusly needs its own port
    port += 1

# create the properly formatted nginx server block
nginx_site_config = f""" 
server {{ 
    listen 80;
    listen [::]:80;
    root /var/www/localhost/html;
    server_name localhost;
    {nginx_config}

    location /index.html {{
        proxy_pass http://localhost:3000/index.html;
    }}

    location ^~ /static/ {{
        proxy_pass http://localhost:3000$request_uri;
    }}

    location /socksjs-node {{
        proxy_pass http://localhost:3000$request_uri;
    }}

    location /manifest.json {{
        proxy_pass http://localhost:3000$request_uri;
    }}

    location /logo192.png {{
        proxy_pass http://localhost:3000$request_uri;
    }}
}}
"""

# write the nginx config
with open("/etc/nginx/sites-available/localhost", "w") as f:
    f.write(nginx_site_config)

# start the ui
os.system(
    "npm install --prefix ./workspace/src/ui && npm start --prefix ./workspace/src/ui &")
