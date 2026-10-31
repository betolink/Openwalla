# OpenWalla Web Dashboard

React + TypeScript + Tailwind dashboard for the OpenWalla control plane.

## Local development

```sh
npm install
npm run dev        # http://127.0.0.1:5173
```

The dev server proxies `/api` to the FastAPI backend at
`http://127.0.0.1:8000`.

## Tests and build

```sh
npm test
npm run build
```

## Connecting a router

Open the dashboard, go to **Router setup**, and enter the router's LAN
address, username and password. The backend uses LuCI RPC
(`cgi-bin/luci/admin/ubus`) to sync devices and interfaces. Credentials are
stored by the backend and never returned to the browser.
