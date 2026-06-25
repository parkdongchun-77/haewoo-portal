// Supabase 연결 설정과 RPC 호출 헬퍼 (근태 시스템 공용)
const SB_URL = "https://kusfsjkuwnbrtccjjfkm.supabase.co";
const SB_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt1c2Zzamt1d25icnRjY2pqZmttIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzOTM2MzIsImV4cCI6MjA5Nzk2OTYzMn0.mQeQVr4t-AWukGT5fIpVrMAG-YtmGSnoqIHeIeGj7GI";

async function rpc(fn, args) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SB_KEY, Authorization: "Bearer " + SB_KEY, "Content-Type": "application/json" },
    body: JSON.stringify(args || {})
  });
  if (!r.ok) { const t = await r.text(); throw new Error("RPC " + fn + " " + r.status + ": " + t); }
  return await r.json();
}
