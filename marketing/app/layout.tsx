import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("http://localhost:3000"),
  title: "2mintogood · A two-minute reset for your body",
  description:
    "A gentle, private macOS desktop companion for short standing breaks that protect your flow.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
  openGraph: {
    title: "2mintogood · A two-minute reset for your body",
    description:
      "A gentle, private macOS desktop companion for short standing breaks that protect your flow.",
    images: [{ url: "/og.png", width: 1698, height: 909 }],
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
