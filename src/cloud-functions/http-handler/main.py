from flask import Request, Response
import json
from db import db
from sqlalchemy import text


def http_handler(request: Request):
    method = request.method.upper()

    with db.connect() as conn:
        if method == "GET":
            results = conn.execute("SELECT name FROM items").fetchall()
            results = [result[0] for result in results]
            return Response(json.dumps(results), status=200)
        elif method == "POST":
            conn.execute(text("INSERT INTO items (name) VALUES (:name)"),
                         name=request.data.decode("UTF-8"))

    return Response(status=200)
