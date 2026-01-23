import { useState, useEffect } from 'react';
import { useNavigate, Link, useSearchParams } from 'react-router-dom';
import { login, register } from '../../api/authApi';
import { useToast } from '../../components/common/ToastProvider';

/**
 * Login Page - Auth APIs
 * POST /api/v1/auth/login
 * POST /api/v1/auth/register
 * 
 * Supports query params:
 * - returnTo: URL to redirect after successful auth (e.g. /products/1#reviews)
 * - mode: initial mode (login or register)
 */
export default function LoginPage() {
    const navigate = useNavigate();
    const [searchParams] = useSearchParams();
    const { notify } = useToast();
    
    // Read query params
    const returnTo = searchParams.get('returnTo') || '/';
    const initialMode = searchParams.get('mode') || 'login';
    
    const [mode, setMode] = useState(initialMode);
    const [loading, setLoading] = useState(false);
    const [isAuthenticated, setIsAuthenticated] = useState(false);

    const [form, setForm] = useState({
        username: 'alice',
        email: 'alice@example.com',
        password: 'password123'
    });

    // Check if user is already authenticated
    useEffect(() => {
        const token = localStorage.getItem('authToken');
        setIsAuthenticated(!!token);
    }, []);
    
    // Update mode when query param changes
    useEffect(() => {
        if (initialMode === 'login' || initialMode === 'register') {
            setMode(initialMode);
        }
    }, [initialMode]);

    const handleLogout = () => {
        localStorage.removeItem('authToken');
        localStorage.removeItem('authUser');
        setIsAuthenticated(false);
        // Dispatch storage event so App.jsx updates header immediately
        window.dispatchEvent(new Event('storage'));
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setLoading(true);

        try {
            let result;
            if (mode === 'login') {
                result = await login(form.username, form.password);
                if (import.meta.env.DEV) {
                    console.log('[API] POST /auth/login:', result);
                }
            } else {
                result = await register(form.username, form.email, form.password);
                if (import.meta.env.DEV) {
                    console.log('[API] POST /auth/register:', result);
                }
            }

            if (result.token) {
                localStorage.setItem('authToken', result.token);
                // Dispatch storage event so App.jsx updates header immediately
                window.dispatchEvent(new Event('storage'));
            }
            
            // Persist user info for review submissions etc.
            if (result.user) {
                localStorage.setItem('authUser', JSON.stringify(result.user));
            }

            notify('success', `${mode === 'login' ? 'Login' : 'Registration'} successful!`);
            // Redirect to returnTo URL (or home)
            setTimeout(() => navigate(returnTo), 800);
        } catch (err) {
            notify('error', err.message || 'Authentication failed');
            if (import.meta.env.DEV) {
                console.error('[API ERROR]', err);
            }
        } finally {
            setLoading(false);
        }
    };

    // Already authenticated - show message + CTA
    if (isAuthenticated) {
        return (
            <div className="auth-page">
                <div className="auth-form">
                    <h2>Already Logged In</h2>
                    <div className="success" style={{ marginBottom: '1rem' }}>
                        You are already logged in.
                    </div>
                    <button
                        className="primary"
                        style={{ width: '100%', marginBottom: '0.5rem' }}
                        onClick={() => navigate('/')}
                    >
                        Go to Products
                    </button>
                    <button
                        style={{ width: '100%' }}
                        onClick={handleLogout}
                    >
                        Logout
                    </button>
                </div>
            </div>
        );
    }

    return (
        <div className="auth-page">
            <div className="auth-form">
                <Link to="/" className="back-link">← Back</Link>
                <h2>{mode === 'login' ? 'Login' : 'Register'}</h2>
                <p className="api-label">
                    API: POST /api/v1/auth/{mode === 'login' ? 'login' : 'register'}
                </p>

                <form onSubmit={handleSubmit}>
                    <div className="form-group">
                        <label>Username</label>
                        <input
                            type="text"
                            placeholder="alice"
                            value={form.username}
                            onChange={(e) => setForm({ ...form, username: e.target.value })}
                            required
                        />
                    </div>

                    {mode === 'register' && (
                        <div className="form-group">
                            <label>Email</label>
                            <input
                                type="email"
                                placeholder="user@example.com"
                                value={form.email}
                                onChange={(e) => setForm({ ...form, email: e.target.value })}
                                required
                            />
                        </div>
                    )}

                    <div className="form-group">
                        <label>Password</label>
                        <input
                            type="password"
                            value={form.password}
                            onChange={(e) => setForm({ ...form, password: e.target.value })}
                            required
                        />
                    </div>

                    <button type="submit" className="primary" style={{ width: '100%' }} disabled={loading}>
                        {loading ? 'Please wait...' : (mode === 'login' ? 'Login' : 'Register')}
                    </button>
                </form>

                <div className="auth-toggle">
                    {mode === 'login' ? (
                        <p>
                            No account?{' '}
                            <button onClick={() => setMode('register')}>Register</button>
                        </p>
                    ) : (
                        <p>
                            Have account?{' '}
                            <button onClick={() => setMode('login')}>Login</button>
                        </p>
                    )}
                </div>
            </div>
        </div>
    );
}
