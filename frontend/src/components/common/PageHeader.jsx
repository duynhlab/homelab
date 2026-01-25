import { Link } from 'react-router-dom';

/**
 * PageHeader Component
 * Standard page title with optional back link and right-side actions
 * 
 * Usage:
 *   <PageHeader title="My Orders" />
 *   <PageHeader title="Order Details" backLink="/orders" backText="Back to Orders" />
 *   <PageHeader title="Cart" actions={<button>Clear Cart</button>} />
 */
export default function PageHeader({ 
    title, 
    backLink, 
    backText = '← Back',
    apiLabel,
    actions,
    children 
}) {
    return (
        <div className="page-header">
            <div className="page-header-top">
                <div className="page-header-left">
                    {backLink && (
                        <Link to={backLink} className="back-link">
                            {backText}
                        </Link>
                    )}
                    <h2>{title}</h2>
                </div>
                {actions && (
                    <div className="page-header-actions">
                        {actions}
                    </div>
                )}
            </div>
            {apiLabel && (
                <p className="api-label">{apiLabel}</p>
            )}
            {children}
        </div>
    );
}
