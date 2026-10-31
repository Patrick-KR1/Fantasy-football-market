import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  cacheComponents: true,
  async redirects() {
    return [{ source: "/players", destination: "/market", permanent: true }];
  },
};

export default nextConfig;
