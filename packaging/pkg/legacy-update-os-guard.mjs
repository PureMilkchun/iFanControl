// Admission for ZIP updaters that never check the OS requirement.
// The maintainer authorized replacing build52 with the macOS15 repack.
// A missing/unrecognized OS is deliberately not treated as compatible.
export async function legacyUpdateOSGuard({ request, next }) {
    const agent = request.headers.get("user-agent") || "";
    const darwin = /\bDarwin\/(\d{1,3})(?:\.|\s|$)/.exec(agent);
    const nativeClient = /\bCFNetwork\//.test(agent);
    if (nativeClient && darwin && Number(darwin[1]) >= 24) {
        const original = await next();
        const headers = new Headers(original.headers);
        headers.set("Cache-Control", "no-store");
        headers.set("Vary", "User-Agent");
        return new Response(original.body, {
            status: original.status, statusText: original.statusText, headers
        });
    }

    // Existing clients compare latest_build before looking at any asset URL.
    // Zero pauses this unsafe upgrade even when the local build is unavailable.
    const paused = {
        latest_version: "2.9.8",
        latest_build: 0,
        notes: "新版需要macOS15或更新版本。旧系统或无法识别系统的自动升级暂已暂停；如出现兼容性问题，可前往GitHub下载2.9.8。",
        minimum_macos: "15.0",
        fallback_url: "https://github.com/PureMilkchun/iFanControl/releases/tag/v2.9.8",
        update_paused: true,
        assets: null
    };
    return new Response(request.method === "HEAD" ? null : JSON.stringify(paused), {
        status: 200,
        headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
            "Vary": "User-Agent",
            "X-iFanControl-Update-Guard": "minimum-os-15"
        }
    });
}
