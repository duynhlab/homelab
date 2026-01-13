import { useState } from 'react';
import './ProductFilter.css';

/**
 * ProductFilter Component
 * Search and filter controls for product catalog
 */
const CATEGORIES = ['Electronics', 'Computers', 'Accessories', 'Peripherals'];
const SORT_OPTIONS = [
    { value: '', label: 'Default' },
    { value: 'price:asc', label: 'Price: Low to High' },
    { value: 'price:desc', label: 'Price: High to Low' },
    { value: 'name:asc', label: 'Name: A-Z' },
    { value: 'name:desc', label: 'Name: Z-A' },
];

export default function ProductFilter({ filters, onFilterChange }) {
    const [searchInput, setSearchInput] = useState(filters.search || '');

    const handleSearchSubmit = (e) => {
        e.preventDefault();
        onFilterChange({ search: searchInput });
    };

    const handleCategoryChange = (category) => {
        onFilterChange({
            category: filters.category === category ? '' : category
        });
    };

    const handleSortChange = (e) => {
        const value = e.target.value;
        if (value) {
            const [sort, order] = value.split(':');
            onFilterChange({ sort, order });
        } else {
            onFilterChange({ sort: '', order: '' });
        }
    };

    const handleClearFilters = () => {
        setSearchInput('');
        onFilterChange({ search: '', category: '', sort: '', order: '' });
    };

    const hasActiveFilters = filters.search || filters.category || filters.sort;

    return (
        <div className="product-filter">
            {/* Search */}
            <form className="product-filter__search" onSubmit={handleSearchSubmit}>
                <input
                    type="text"
                    placeholder="Search products..."
                    value={searchInput}
                    onChange={(e) => setSearchInput(e.target.value)}
                    className="product-filter__search-input"
                />
                <button type="submit" className="product-filter__search-btn">
                    🔍
                </button>
            </form>

            {/* Categories */}
            <div className="product-filter__categories">
                {CATEGORIES.map((category) => (
                    <button
                        key={category}
                        className={`product-filter__category ${filters.category === category ? 'active' : ''
                            }`}
                        onClick={() => handleCategoryChange(category)}
                    >
                        {category}
                    </button>
                ))}
            </div>

            {/* Sort & Clear */}
            <div className="product-filter__actions">
                <select
                    value={filters.sort ? `${filters.sort}:${filters.order}` : ''}
                    onChange={handleSortChange}
                    className="product-filter__sort"
                >
                    {SORT_OPTIONS.map((option) => (
                        <option key={option.value} value={option.value}>
                            {option.label}
                        </option>
                    ))}
                </select>

                {hasActiveFilters && (
                    <button
                        className="product-filter__clear"
                        onClick={handleClearFilters}
                    >
                        Clear Filters
                    </button>
                )}
            </div>
        </div>
    );
}
