var p=`
  <div class="isabelle-config">
    <label>Server
      <select name="server">
        <option value="local">start one</option>
        <option value="host">connect by host and port</option>
        <option value="url">connect by URL</option>
      </select>
    </label>
    <label class="url">URL <input name="url" size="32" placeholder="wss://\u2026/isabelle" /></label>
    <label class="host">Host <input name="host" size="15" placeholder="127.0.0.1" /></label>
    <label class="host">Port <input name="port" type="number" min="1" max="65535" /></label>
    <span class="remote">
      <label>Password <input name="password_secret" size="18" placeholder="Livebook secret" /></label>
      <button type="button" class="select-secret">Select</button>
    </span>
    <label class="remote">Sessions
      <input name="sessions" size="40" placeholder="HOL=&lt;session id&gt; \u2026" />
    </label>
  </div>
`;function d(t,i){t.importCSS("main.css"),t.root.innerHTML=p;let o=t.root.querySelector(".isabelle-config"),e=s=>o.querySelector(`[name="${s}"]`);function c(){let s=e("port").value;return{server:e("server").value,url:e("url").value.trim(),host:e("host").value.trim(),port:s===""?null:Number(s),password_secret:e("password_secret").value.trim(),sessions:e("sessions").value.split(/\s+/).filter(l=>l!=="").map(l=>l.split("="))}}function r(){t.pushEvent("update",c())}function a(){o.dataset.server=e("server").value}function n(s){e("server").value=s.server,e("url").value=s.url,e("host").value=s.host,e("port").value=s.port??"",e("password_secret").value=s.password_secret,e("sessions").value=Object.entries(s.sessions).map(l=>l.join("=")).join(" "),a()}for(let s of["server","url","host","port","password_secret","sessions"])e(s).addEventListener("change",()=>{a(),r()});o.querySelector(".select-secret").addEventListener("click",()=>t.selectSecret(s=>{e("password_secret").value=s,r()},e("password_secret").value||"ISABELLE_PASSWORD")),t.handleSync(r),t.handleEvent("fields",n),n(i)}export{d as init};
