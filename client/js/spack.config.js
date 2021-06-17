module.exports = {
    entry: {
        web: __dirname + "/src/index.ts",
    },
    output: {
        path: __dirname + "../../../priv/static/",
        name: "live_data_client.js",
    },
    options: {
        env: {
            targets: "> 1.00%, not dead"
        }
    }
};
