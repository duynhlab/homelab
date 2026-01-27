import { useState, useEffect } from 'react';
import ProductGrid from '../../components/domain/ProductGrid';
import { GridSkeleton } from '../../components/common/Skeleton';
import EmptyState from '../../components/common/EmptyState';
import ApiError from '../../components/common/ApiError';
import { useProducts } from '../../hooks/useProducts';

/**
 * HomePage - Product Catalog
 * API: GET /api/v1/products
 * 
 * Responsibilities:
 * - Fetch products from API (using useProducts hook with SWR)
 * - Handle loading/error/empty states
 * - Pass data to domain components
 */
export default function HomePage() {
    const [page, setPage] = useState(1);
    const limit = 30;
    const { products, total, totalPages, loading, error } = useProducts({ page, limit });

    // Scroll to top when page changes
    useEffect(() => {
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }, [page]);

    return (
        <div className="page container">
            <h2>Products</h2>
            <p className="api-label">API: GET /api/v1/products • {total} items • Page {page} of {totalPages}</p>

            {/* Loading State */}
            {loading && <GridSkeleton count={8} />}

            {/* Error State */}
            {!loading && error && (
                <ApiError error={error} endpoint="GET /api/v1/products" />
            )}

            {/* Empty State */}
            {!loading && !error && products.length === 0 && (
                <EmptyState message="No products available" icon="📦" />
            )}

            {/* Success State */}
            {!loading && !error && products.length > 0 && (
                <>
                    <ProductGrid products={products} />

                    {/* Pagination Controls */}
                    <div className="pagination-controls" style={{ display: 'flex', justifyContent: 'center', gap: '1rem', marginTop: '2rem' }}>
                        <button
                            disabled={page === 1}
                            onClick={() => setPage(p => Math.max(1, p - 1))}
                            className="btn btn-secondary"
                        >
                            Previous
                        </button>
                        <span style={{ alignSelf: 'center' }}>
                            Page {page} of {totalPages}
                        </span>
                        <button
                            disabled={page >= totalPages}
                            onClick={() => setPage(p => p + 1)}
                            className="btn btn-secondary"
                        >
                            Next
                        </button>
                    </div>
                </>
            )}

            {/* API Debug */}
            <details className="api-debug">
                <summary>API Response</summary>
                <pre>{JSON.stringify(products, null, 2)}</pre>
            </details>
        </div>
    );
}
