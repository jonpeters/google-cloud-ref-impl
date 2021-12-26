import os
import sqlalchemy

db_config = {
    "pool_size": 5,
    "max_overflow": 2,
    "pool_timeout": 30,  # 30 seconds
    "pool_recycle": 1800,  # 30 minutes
}


def init():
    USER = os.getenv("USER")
    PASSWORD = os.getenv("PASSWORD")
    DATABASE = os.getenv("DATABASE")
    CONNECTION_NAME = os.getenv("CONNECTION_NAME")
    HOST = os.getenv("HOST")

    engine_args = {
        "drivername": "postgresql+pg8000",
        "username": USER,
        "password": PASSWORD,
        "database": DATABASE,
    }

    # local / cloud sql proxy
    if HOST:
        engine_args["host"] = HOST
        engine_args["port"] = 5432
    # cloud
    else:
        engine_args["query"] = {
            "unix_sock": f"/cloudsql/{CONNECTION_NAME}/.s.PGSQL.5432"
        }

    return sqlalchemy.create_engine(sqlalchemy.engine.url.URL.create(**engine_args), **db_config)


def create_tables():
    global db
    with db.connect() as conn:
        conn.execute(
            """CREATE TABLE IF NOT EXISTS items (
            id serial primary key,
            name text
            )"""
        )


# Connections to underlying databases may be dropped, either by the database
# server itself, or by the infrastructure underlying Cloud Functions.
# We recommend using a client library that supports connection pools that
# automatically reconnect broken client connections. Additionally, we
# recommend using a globally scoped connection pool to increase the
# likelihood that your function reuses the same connection for subsequent
# invocations of the function, and closes the connection naturally when the
# instance is evicted (auto-scaled down)
db = init()
create_tables()
