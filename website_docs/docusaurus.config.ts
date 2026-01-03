import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'pg_ttl_index',
  tagline: 'Automatic Time-To-Live (TTL) data expiration for PostgreSQL',
  favicon: 'img/favicon.ico',

  future: {
    v4: true,
  },

  url: 'https://ibrahimkarimeddin.github.io',
  baseUrl: '/',

  organizationName: 'ibrahimkarimeddin',
  projectName: 'postgres-extensions-pg_ttl',

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl:
            'https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/tree/main/website_docs/',
        },
        blog: {
          showReadingTime: true,
          feedOptions: {
            type: ['rss', 'atom'],
            xslt: true,
          },
          editUrl:
            'https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/tree/main/website_docs/',
        },
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/pg-ttl-social-card.jpg',
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'pg_ttl_index',
      logo: {
        alt: 'pg_ttl_index Logo',
        src: 'img/pg_ttl_logo.png',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Documentation',
        },
        {
          to: '/docs/api/functions',
          label: 'API Reference',
          position: 'left'
        },
        {to: '/blog', label: 'Blog', position: 'left'},
        {
          href: 'https://pgxn.org/dist/pg_ttl_index/',
          label: 'PGXN',
          position: 'right',
        },
        {
          href: 'https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Documentation',
          items: [
            {
              label: 'Getting Started',
              to: '/docs/intro',
            },
            {
              label: 'Installation',
              to: '/docs/installation',
            },
            {
              label: 'API Reference',
              to: '/docs/api/functions',
            },
          ],
        },
        {
          title: 'Community',
          items: [
            {
              label: 'GitHub Issues',
              href: 'https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues',
            },
            {
              label: 'GitHub Discussions',
              href: 'https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/discussions',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'PGXN',
              href: 'https://pgxn.org/dist/pg_ttl_index/',
            },
            {
              label: 'GitHub',
              href: 'https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl',
            },
            {
              label: 'Blog',
              to: '/blog',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Ibrahim Karim Eddin. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['sql', 'bash'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
