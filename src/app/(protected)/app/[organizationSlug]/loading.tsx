import { Card } from "@/components/ui/card";

export default function LoadingDashboard(){return <div aria-busy="true" aria-label="Carregando dashboard" className="space-y-5"><div className="h-24 animate-pulse rounded-xl bg-[#edf2ee]"/><div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{Array.from({length:4},(_,i)=><Card key={i} className="h-28 animate-pulse bg-[#f5f7f5]"/>)}</div><Card className="h-72 animate-pulse bg-[#f5f7f5]"/></div>}
