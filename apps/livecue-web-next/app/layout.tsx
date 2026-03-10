import type { Metadata } from 'next';

import './globals.css';

export const metadata: Metadata = {
  title: 'LiveCue Viewer',
  description: 'Next.js canvas viewer for LiveCue Safari stability'
};

export default function RootLayout({
  children
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
