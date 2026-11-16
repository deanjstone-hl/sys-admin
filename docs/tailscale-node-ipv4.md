# Tailscale on WSL2 — Node.js needs IPv4

Moved here from argus `context/tools.md` ([argus#418](https://github.com/deanjstone/argus/issues/418)):
it is a property of this machine's network stack, not of any one project.

WSL2 + Tailscale breaks Node.js happy-eyeballs IPv6. Any script calling `api.telegram.org` needs:

```javascript
const options = {
  hostname: 'api.telegram.org',
  family: 4,  // REQUIRED on WSL2 + Tailscale
  // ...
};
```

Apply to any new script that calls the Telegram API.

