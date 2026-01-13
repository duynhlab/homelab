/**
 * PlaceholderImage Component
 * Static placeholder for all product images
 * API-agnostic - no backend assumptions
 */
export default function PlaceholderImage({ size = 'medium', label = 'Product' }) {
    const dimensions = {
        small: '100',
        medium: '400',
        large: '600'
    };

    const dim = dimensions[size] || dimensions.medium;

    return (
        <svg viewBox={`0 0 ${dim} ${dim}`} fill="none" style={{ width: '100%', height: '100%' }}>
            <rect width={dim} height={dim} fill="#2a2a2a" />
            <text
                x={dim / 2}
                y={dim / 2}
                textAnchor="middle"
                fill="#555"
                fontSize={dim / 16}
            >
                {label}
            </text>
        </svg>
    );
}
