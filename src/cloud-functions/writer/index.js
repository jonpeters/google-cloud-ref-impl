const { PubSub } = require('@google-cloud/pubsub');
const { Pool } = require('pg');

exports.writer = async (req, res) => {
    const { USER, PASSWORD, DATABASE, CONNECTION_NAME } = process.env;
    const pool = new Pool({
        max: 1,
        user: USER,
        password: PASSWORD,
        host: `/cloudsql/${CONNECTION_NAME}`,
        database: DATABASE
    });
    const { rows } = await pool.query("select name from items");
    res.status(200).send(`Got ${rows[0].name}`);
}