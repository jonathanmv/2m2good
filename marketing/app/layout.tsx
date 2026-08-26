import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("http://localhost:3000"),
  title: "2m2better · Two minutes for your body",
  description:
    "A small, local macOS developer preview for a two-minute movement reset between screen-heavy stretches.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
  openGraph: {
    title: "2m2better · Two minutes for your body",
    description:
      "A small, local macOS developer preview for a two-minute movement reset between screen-heavy stretches.",
    images: [{ url: "/og.png", width: 1730, height: 909 }],
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    images: ["/og.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
