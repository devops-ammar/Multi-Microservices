const REDIS_URL = process.env.REDIS_URL || "redis://redis:6379";
const MONGO_URL =
  process.env.MONGO_URL || "mongodb://admin:password@mongo:27017/";

module.exports = {
  MONGO_URL,
  REDIS_URL,
};
