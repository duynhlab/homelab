import { useState, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { login, register } from '../../api/authApi';

/**
 * Login Page - Auth APIs
 * POST /api/v1/auth/login
 * POST /api/v1/auth/register
 */
export default function LoginPage() {
    const navigate = useNavigate();
    const [mode, setMode] = useState('login');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [success, setSuccess] = useState(null);
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

    const handleLogout = () => {
        localStorage.removeItem('authToken');
        setIsAuthenticated(false);
        // Dispatch storage event so App.jsx updates header immediately
        window.dispatchEvent(new Event('storage'));
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setLoading(true);
        setError(null);
        setSuccess(null);

        try {
            let result;
            if (mode === 'login') {
                result = await login(form.username, form.password);
                console.log('[API] POST /auth/login:', result);
            } else {
                result = await register(form.username, form.email, form.password);
                console.log('[API] POST /auth/register:', result);
            }

            if (result.token) {
                localStorage.setItem('authToken', result.token);
                // Dispatch storage event so App.jsx updates header immediately
                window.dispatchEvent(new Event('storage'));
            }

            setSuccess(`${mode === 'login' ? 'Login' : 'Registration'} successful!`);
            setTimeout(() => navigate('/'), 1000);
        } catch (err) {
            setError(err.message);
            console.error('[API ERROR]', err);
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

                {error && <div className="error">{error}</div>}
                {success && <div className="success">{success}</div>}

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
