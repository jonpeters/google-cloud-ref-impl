import os
import json
from jsonpath_rw import jsonpath
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


# TODO read this from command line args
project_id = "yet-another-335918"

# read the terraform state file
tf_state = json.load(open("terraform/terraform.tfstate"))

# start cloud_sql_proxy
master_instance_name = read_output_value("master-db-connection-name")
os.system(
    f"./cloud_sql_proxy -instances={master_instance_name}=tcp:5432 &>/dev/null &")

# start pubsub emulator
os.system(f"gcloud beta emulators pubsub start --project=\"{project_id}\" &")
export_command = os.popen("gcloud beta emulators pubsub env-init").read()
env_var = export_command.split(" ")[1]
env_var_name, env_var_value = env_var.split("=")
os.environ[env_var_name] = env_var_value


# read the cloud functions triggered by pubsub and create the topics they listen to
expression = parse(
    """$.resources[?type=="google_cloudfunctions_function"].instances[*].attributes.
    event_trigger[?event_type=="providers/cloud.pubsub/eventTypes/topic.publish"].resource""")
for resource in {match.value for match in expression.find(tf_state)}:
    create_topic(resource)

# start each function inside functions-framework
port = 8080
for cf_dir in os.scandir("src/cloud-functions"):
    dir_name = cf_dir.path.split("/")[-1]
    expression = parse(
        f"""$.resources[?type=="google_cloudfunctions_function"].instances[?attributes.labels.
        directory_name=="{dir_name}"].attributes.environment_variables""")
    env_vars = expression.find(tf_state)[0].value
    # host needs to be set for local function execution
    env_vars["HOST"] = "localhost"
    env_vars_formatted = " ".join(
        [f"{key}={value}" for key, value in env_vars.items()])

    ff_command = f"""{env_vars_formatted} functions-framework --port {port} --source ./{cf_dir.path}/main.py --target entry_point --debug &>/dev/null &""" 

    os.system(ff_command)
    print(f"started function '{dir_name}'")

    # determine if this is a function that subscribes to a topic
    expression = parse(
        f"""$.resources[?type=="google_cloudfunctions_function"].instances[?attributes.labels.
        directory_name=="{dir_name}"].attributes.event_trigger[?event_type="providers/cloud.pubsub/eventTypes/topic.publish"].resource""")
    matches = expression.find(tf_state)
    if len(matches):
        create_subscription(matches[0].value, f"http://localhost:{port}")

    port += 1
