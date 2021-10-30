const { Pool } = require('pg');

exports.writer = async (req, res) => {
    const { body } = req;
    const { USER, PASSWORD, DATABASE, CONNECTION_NAME } = process.env;

    // init the connection
    const pool = new Pool({
        max: 1,
        user: USER,
        password: PASSWORD,
        host: `/cloudsql/${CONNECTION_NAME}`,
        database: DATABASE
    });

    // create the table
    const ddl = `
        CREATE TABLE IF NOT EXISTS items (
            id serial primary key,
            name text
        );
    `;
    await pool.query(ddl);

    // insert user data
    const query = {
        text: 'INSERT INTO items (name) VALUES ($1)',
        values: [body],
    }
    await pool.query(query);

    res.status(200).send(`Wrote ${body}`);
}