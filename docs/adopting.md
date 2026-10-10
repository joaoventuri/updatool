# Moving an existing app to updatool

You probably have one container (`app`) behind a proxy today. The move is done
with the app online.

1. **Install and init** on the server: `updatool init`, then edit `updatool.conf`
   (same network, env file and volumes you use today in `RUN_ARGS`).
2. **Point the route file to a new name.** If your proxy already routes to
   `app`, give updatool its own file (`TRAEFIK_FILE=…/app-updatool.yml`) and keep
   your current route until step 4.
3. **First ship**: `updatool ship`. It starts `app-blue`, waits for health and
   writes the route. Test the new route (a temporary host rule is handy).
4. **Cut over**: remove your old route/service so the updatool file is the only
   one serving the domain. Traffic now goes to `app-blue`.
5. **Retire the old container** once nothing reaches it (`docker logs -f app`
   goes quiet): `docker stop app`.
6. **Rehearse**: `updatool ship --force` (same version into green) and
   `updatool rollback`. Both should be invisible to users.
7. **Tell everyone who deploys**: from now on, only `updatool ship`. A manual
   `docker compose up` on the old service would fight the slots.

Companion containers (workers, cron) that must run the same version: restart
them in `HOOK_POST_SWITCH`, e.g.
`HOOK_POST_SWITCH='docker rm -f app-worker; docker run -d --name app-worker … app:$UPDATOOL_VERSION node worker.js'`.
