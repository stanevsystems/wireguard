# Copy to proxy-secrets.local.ps1 (gitignored). Do not commit the real password.
# VM upstream is the JVM corp-proxy (java -jar corp-proxy.jar), not 3proxy and not
# IntelliJ Settings -> HTTP Proxy. Same user/password/port go into
# %USERPROFILE%\.corp-proxy\secrets.local.yaml on the VM (see vm-corp-proxy/corp-proxy/README.md).
# After edits run sync-corp-vm-from-secrets.ps1 and reload v2rayN.
$UpstreamHost     = '192.168.136.140'
$UpstreamPort     = 3332
$UpstreamUser     = 'admin'
$UpstreamPassword = 'CHANGE_ME'
$ListenPort       = 3128
