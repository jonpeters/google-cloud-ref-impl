FROM ubuntu:20.04
WORKDIR /app
RUN apt-get update
RUN apt-get install -y curl dialog apt-utils zip software-properties-common gnupg wget default-jre
RUN add-apt-repository ppa:deadsnakes/ppa
RUN apt-get update
RUN apt install -y python3.9 python3-pip nginx
RUN touch /etc/nginx/sites-available/localhost
RUN ln -s /etc/nginx/sites-available/localhost /etc/nginx/sites-enabled/
COPY requirements.txt .
RUN pip3 install -r requirements.txt
RUN curl -sSL https://sdk.cloud.google.com | bash
ENV PATH $PATH:/root/google-cloud-sdk/bin
RUN gcloud components update
RUN gcloud components install pubsub-emulator beta
COPY run.py /app/
RUN wget --directory-prefix=/app/ https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
RUN chmod +x /app/cloud_sql_proxy
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh
CMD [ "bash", "/app/start.sh" ]