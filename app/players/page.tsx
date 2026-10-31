import { redirect } from "next/navigation";
// next.config preserves legacy query strings before this fallback is reached.
export default function Page() { redirect("/market"); }
