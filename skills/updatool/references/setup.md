# Setting up updatool for an app (agent checklist)

1. **Server access**: confirm you are on the production host (or can SSH to it)
   and that `docker info` works for the current user.
2. **Install** (if `command -v updatool` fails):
   `curl -fsSL https://raw.githubusercontent.com/joaoventuri/updatool/main/install.sh | sh`
3. **Init** in the project directory on the server: `updatool init`.
4. **Fill `updatool.conf` with the user** — do not guess production values:
   - `PORT`: port the app listens on inside the container.
   - `HEALTH_PATH`: an endpoint that returns 2xx/3xx only when the app can serve.
   - `NETWORK`: the docker network the proxy uses (`docker network ls`,
     `docker inspect <proxy>`); or `SLOT_HOST_PORTS` if the proxy runs on the host.
   - Proxy block (`docs/proxies.md`): Traefik needs the file provider on a
     mounted **directory**.
   - `RUN_ARGS`: copy env-file, volumes, memory limits from how the app runs today.
   - `CHECK_CMD`: the project's type check + tests.
   - `BUILD_CPUS`: on a shared host, about half the cores.
5. **`updatool doctor`** until everything is green (cache mounts included).
6. **First ship on a new route** (keep the old one until verified), then cut over
   (`docs/adopting.md`).
7. **Rehearse rollback** once, while the user watches.
8. Tell the user that from now on every deploy must go through `updatool ship`.
