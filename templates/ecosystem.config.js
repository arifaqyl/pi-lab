// ~/ecosystem.config.js
//
// The whole inventory of what runs. One entry per long-lived Python
// process. Each uses its own venv interpreter so dependencies never
// collide. Secrets go in `env` here (this file is not committed) or in a
// .env the app reads; never in the repo.
module.exports = {
  apps: [
    {
      name: "trafficmy-api",
      script: "run_server.py",
      cwd: "/home/pi/aduanmy",
      interpreter: "/home/pi/aduanmy/.venv/bin/python3",
      env: {
        PORT: "8002",
        ADUANMY_ENV: "production",
        ADUANMY_DB_PATH: "/home/pi/aduanmy/data/aduanmy.db",
        ADUANMY_DATA_DIR: "/home/pi/aduanmy/data",
        ADUANMY_AUTO_REFRESH_ENABLED: "true",
        ADUANMY_FULL_REFRESH_INTERVAL_SECONDS: "900",
        ADUANMY_TELEGRAM_BOT_TOKEN: "<from BotFather>",
        ADUANMY_TELEGRAM_OPS_CHAT_ID: "<your chat id>"
      }
    },
    {
      name: "kedai-ops-api",
      script: "run_server.py",
      cwd: "/home/pi/kedai-ops",
      interpreter: "/home/pi/kedai-ops/.venv/bin/python3",
      env: { PORT: "8000", KEDAI_OPS_ENV: "production", DB_PATH: "/home/pi/kedai-ops/data/sah_bukti.db" }
    },
    {
      // An app mounted under a path must be told its prefix so links resolve.
      name: "ops-console",
      script: "run_ops_console.py",
      cwd: "/home/pi/student-bot",
      interpreter: "/home/pi/student-bot/.venv/bin/python3",
      env: { OPS_CONSOLE_HOST: "0.0.0.0", OPS_CONSOLE_PORT: "8091", OPS_CONSOLE_URL_PREFIX: "/ops-console" }
    },
    {
      // Long-polling bots and workers have no port; PM2 just keeps them alive.
      name: "student-bot",
      script: "bot.py",
      cwd: "/home/pi/student-bot",
      interpreter: "/home/pi/student-bot/.venv/bin/python3"
    }
  ]
};
