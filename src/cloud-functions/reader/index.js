const { Pool } = require('pg');

exports.reader = async (req, res) => {
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
    const { rows } = await pool.query('SELECT name FROM items');
    const results = rows.map(({ name }) => name);

    res.status(200).send(JSON.stringify(results, null, 2));
}