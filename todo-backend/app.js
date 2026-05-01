const express = require("express");
const logger = require("morgan");
const cors = require("cors");

const indexRouter = require("./routes/index");
const todosRouter = require("./routes/todos");

const app = express();

app.use(cors());

app.use(logger("dev"));
app.use(express.json());

app.get('/health', (req, res) => res.status(200).send('OK'));

app.use("/", indexRouter);
app.use("/todos", todosRouter);


module.exports = app;
