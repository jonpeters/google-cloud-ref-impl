const { PubSub } = require('@google-cloud/pubsub');

exports.writer = async (req, res) => {
    const value = process.env.PROJECT_ID;
    res.status(200).send(`Got ${value}`);
}