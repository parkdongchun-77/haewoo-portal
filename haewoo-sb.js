// Supabase 연결 설정과 RPC 호출 헬퍼 (근태 시스템 공용)
const SB_URL = "https://fnvtdvpfuevzukfndpek.supabase.co";
const SB_KEY = "sb_publishable_VyddPYbK6B8kz1yHUUyN9Q_CDBJf2kd";

async function rpc(fn, args) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SB_KEY, Authorization: "Bearer " + SB_KEY, "Content-Type": "application/json" },
    body: JSON.stringify(args || {})
  });
  if (!r.ok) { const t = await r.text(); throw new Error("RPC " + fn + " " + r.status + ": " + t); }
  return await r.json();
}
