import "./config.css";

const template = `
  <div class="isabelle-config">
    <label>Server
      <select name="server">
        <option value="local">start one</option>
        <option value="host">connect by host and port</option>
        <option value="url">connect by URL</option>
      </select>
    </label>
    <label class="url">URL <input name="url" size="32" placeholder="wss://…/isabelle" /></label>
    <label class="host">Host <input name="host" size="15" placeholder="127.0.0.1" /></label>
    <label class="host">Port <input name="port" type="number" min="1" max="65535" /></label>
    <span class="remote">
      <label>Password <input name="password_secret" size="18" placeholder="Livebook secret" /></label>
      <button type="button" class="select-secret">Select</button>
    </span>
    <label class="remote">Sessions
      <input name="sessions" size="40" placeholder="HOL=&lt;session id&gt; …" />
    </label>
  </div>
`;

export function init(ctx, fields) {
  ctx.importCSS("main.css");
  ctx.root.innerHTML = template;

  const root = ctx.root.querySelector(".isabelle-config");
  const input = (name) => root.querySelector(`[name="${name}"]`);

  function collect() {
    const port = input("port").value;
    return {
      server: input("server").value,
      url: input("url").value.trim(),
      host: input("host").value.trim(),
      port: port === "" ? null : Number(port),
      password_secret: input("password_secret").value.trim(),
      sessions: input("sessions")
        .value.split(/\s+/)
        .filter((pair) => pair !== "")
        .map((pair) => pair.split("=")),
    };
  }

  function sync() {
    ctx.pushEvent("update", collect());
  }

  function showServer() {
    root.dataset.server = input("server").value;
  }

  function render(fields) {
    input("server").value = fields.server;
    input("url").value = fields.url;
    input("host").value = fields.host;
    input("port").value = fields.port ?? "";
    input("password_secret").value = fields.password_secret;
    input("sessions").value = Object.entries(fields.sessions)
      .map((pair) => pair.join("="))
      .join(" ");
    showServer();
  }

  for (const name of ["server", "url", "host", "port", "password_secret", "sessions"]) {
    input(name).addEventListener("change", () => {
      showServer();
      sync();
    });
  }

  root.querySelector(".select-secret").addEventListener("click", () =>
    ctx.selectSecret((name) => {
      input("password_secret").value = name;
      sync();
    }, input("password_secret").value || "ISABELLE_PASSWORD"),
  );

  ctx.handleSync(sync);
  // Sent when the cell rejects a value, to show the fields it kept.
  ctx.handleEvent("fields", render);

  render(fields);
}
