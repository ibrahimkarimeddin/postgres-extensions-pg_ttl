import type {ReactNode} from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  icon: string;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'Automatic Data Expiration',
    icon: '🔄',
    description: (
      <>
        Set TTL rules once and let the background worker handle everything. 
        No manual queries, no cron jobs - just automatic, reliable cleanup.
      </>
    ),
  },
  {
    title: 'High Performance',
    icon: '⚡',
    description: (
      <>
        Batch deletion handles millions of rows efficiently. Auto-created indexes 
        ensure fast cleanup. Advisory locks prevent overlapping runs.
      </>
    ),
  },
  {
    title: 'Built-in Monitoring',
    icon: '📊',
    description: (
      <>
        Track deletion statistics, monitor worker health, and view cleanup history 
        with dedicated SQL views. Production-ready observability out of the box.
      </>
    ),
  },
  {
    title: 'ACID Compliant',
    icon: '🔒',
    description: (
      <>
        Per-table error handling ensures one failure doesn't affect others. 
        Safe, transactional cleanup that never compromises data integrity.
      </>
    ),
  },
  {
    title: 'Zero Configuration',
    icon: '🎯',
    description: (
      <>
        Smart defaults work for most use cases. Auto-indexing, optimal batch sizes, 
        and intelligent cleanup intervals require no tuning to get started.
      </>
    ),
  },
  {
    title: 'Multiple Tables',
    icon: '🗂️',
    description: (
      <>
        Configure different expiration times for different tables. Sessions expire 
        in minutes, logs in days, audit trails in months - all managed automatically.
      </>
    ),
  },
];

function Feature({title, icon, description}: FeatureItem) {
  return (
    <div className={clsx('col col--4', styles.feature)}>
      <div className={styles.featureCard}>
        <div className={styles.featureIcon}>{icon}</div>
        <Heading as="h3" className={styles.featureTitle}>{title}</Heading>
        <p className={styles.featureDescription}>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className={styles.featuresHeader}>
          <Heading as="h2">Why pg_ttl_index?</Heading>
          <p>Everything you need for automatic data expiration in PostgreSQL</p>
        </div>
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
