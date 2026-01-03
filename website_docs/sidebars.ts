import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    {
      type: 'category',
      label: 'Getting Started',
      items: [
        'intro',
        'installation',
        'quick-start',
      ],
    },
    {
      type: 'category',
      label: 'Guides',
      items: [
        'guides/configuration',
        'guides/usage-examples',
        'guides/monitoring',
        'guides/best-practices',
      ],
    },
    {
      type: 'category',
      label: 'API Reference',
      items: [
        'api/functions',
        'api/tables',
        'api/configuration',
      ],
    },
    {
      type: 'category',
      label: 'Advanced Topics',
      items: [
        'advanced/architecture',
        'advanced/performance',
        'advanced/troubleshooting',
        'advanced/migration',
      ],
    },
    {
      type: 'category',
      label: 'Resources',
      items: [
        'faq',
        'changelog',
        'contributing',
      ],
    },
  ],
};

export default sidebars;
