import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import Heading from '@theme/Heading';

import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero', styles.heroBanner)}>
      <div className="container">
        <div className={styles.heroContent}>
          <div className={styles.heroText}>
            <img src={require('@site/static/img/pg_ttl_logo.png').default} alt="pg_ttl_index" className={styles.heroLogo} />
            <Heading as="h1" className={styles.heroTitle}>
              {siteConfig.title}
            </Heading>
            <p className={styles.heroSubtitle}>{siteConfig.tagline}</p>
            <p className={styles.heroDescription}>
              High-performance PostgreSQL extension for automatic data expiration with batch deletion, 
              auto-indexing, and built-in statistics tracking.
            </p>
            <div className={styles.buttons}>
              <Link
                className="button button--primary button--lg"
                to="/docs/intro">
                Get Started →
              </Link>
              <Link
                className="button button--secondary button--lg"
                to="/docs/quick-start">
                Quick Start ⚡
              </Link>
            </div>
            <div className={styles.badges}>
              <span className={styles.badge}>PostgreSQL 12+</span>
              <span className={styles.badge}>Production Ready</span>
              <span className={styles.badge}>v2.0.0</span>
            </div>
          </div>
          <div className={styles.heroCode}>
            <div className={styles.codeBlock}>
              <div className={styles.codeHeader}>
                <span className={styles.codeDot} style={{background: '#ff5f56'}}></span>
                <span className={styles.codeDot} style={{background: '#ffbd2e'}}></span>
                <span className={styles.codeDot} style={{background: '#27c93f'}}></span>
                <span className={styles.codeTitle}>Quick Example</span>
              </div>
              <pre className={styles.codeContent}>
{`-- Start background worker
SELECT ttl_start_worker();

-- Create table
CREATE TABLE sessions (
  id SERIAL PRIMARY KEY,
  data JSONB,
  created_at TIMESTAMPTZ 
    DEFAULT NOW()
);

-- Auto-expire after 1 hour
SELECT ttl_create_index(
  'sessions', 
  'created_at', 
  3600
);

-- That's it! ✨`}
              </pre>
            </div>
          </div>
        </div>
      </div>
    </header>
  );
}

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title="PostgreSQL TTL Extension"
      description="Automatic Time-To-Live (TTL) data expiration for PostgreSQL tables with high-performance batch deletion">
      <HomepageHeader />
      <main>
        <HomepageFeatures />
        
        {/* Stats Section */}
        <section className={styles.statsSection}>
          <div className="container">
            <div className={styles.statsGrid}>
              <div className={styles.statCard}>
                <div className={styles.statNumber}>10K+</div>
                <div className={styles.statLabel}>Rows/Second</div>
              </div>
              <div className={styles.statCard}>
                <div className={styles.statNumber}>0</div>
                <div className={styles.statLabel}>Manual Scripts</div>
              </div>
              <div className={styles.statCard}>
                <div className={styles.statNumber}>100%</div>
                <div className={styles.statLabel}>Automatic</div>
              </div>
            </div>
          </div>
        </section>

        {/* CTA Section */}
        <section className={styles.ctaSection}>
          <div className="container">
            <Heading as="h2">Ready to automate your data cleanup?</Heading>
            <p>Install pg_ttl_index in minutes and never worry about expired data again.</p>
            <div className={styles.ctaButtons}>
              <Link
                className="button button--primary button--lg"
                to="/docs/installation">
                Install Now
              </Link>
              <Link
                className="button button--link button--lg"
                to="https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl">
                View on GitHub →
              </Link>
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}
