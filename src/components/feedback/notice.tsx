export function Notice({ error, success, erro, sucesso }: { error?: string; success?: string; erro?: string; sucesso?: string }) {
  error ??= erro;
  success ??= sucesso;
  const value = error ?? success;
  if (!value) return null;
  return <div role="status" className={`mb-5 rounded-lg border px-4 py-3 text-sm ${error ? "border-red-200 bg-red-50 text-red-800" : "border-emerald-200 bg-emerald-50 text-emerald-800"}`}>{value}</div>;
}
