import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getUserProfile, updateProfile } from '../../api/userApi';
import { useAuth } from '../../hooks/useAuth';
import { useApiQuery } from '../../hooks/useApiQuery';
import { useApiMutation } from '../../hooks/useApiMutation';
import PageHeader from '../../components/common/PageHeader';
import LoadingState from '../../components/common/LoadingState';
import ApiError from '../../components/common/ApiError';
import EmptyState from '../../components/common/EmptyState';
import ApiDebug from '../../components/common/ApiDebug';
import './ProfilePage.css';

/**
 * ProfilePage Component
 * Allows users to view and edit their profile
 * API: GET /api/v1/users/profile
 * API: PUT /api/v1/users/profile
 */
export default function ProfilePage() {
    const navigate = useNavigate();
    const { isAuthenticated, requireAuth } = useAuth();

    // Auth guard
    useEffect(() => {
        requireAuth(navigate, '/profile');
    }, [requireAuth, navigate]);

    // Fetch profile using shared hook
    const { data: profile, loading, error, mutate } = useApiQuery(
        isAuthenticated ? 'user-profile' : null,
        getUserProfile
    );

    // Update mutation
    const { mutate: saveProfile, loading: saving } = useApiMutation(updateProfile, {
        successMessage: 'Profile updated!',
        errorMessage: 'Failed to update profile',
    });

    // Form state
    const [editMode, setEditMode] = useState(false);
    const [formData, setFormData] = useState({
        name: '',
        phone: ''
    });

    // Sync form data when profile loads
    useEffect(() => {
        if (profile) {
            setFormData({
                name: profile.name || '',
                phone: profile.phone || ''
            });
        }
    }, [profile]);

    const handleInputChange = (e) => {
        const { name, value } = e.target;
        setFormData(prev => ({
            ...prev,
            [name]: value
        }));
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        const result = await saveProfile(formData);
        if (result) {
            setEditMode(false);
            mutate(); // Refresh profile data
        }
    };

    const handleCancel = () => {
        setFormData({
            name: profile?.name || '',
            phone: profile?.phone || ''
        });
        setEditMode(false);
    };

    // Auth gate
    if (!isAuthenticated) {
        return (
            <div className="page container">
                <PageHeader title="My Profile" backLink="/" backText="← Back to Home" />
                <EmptyState message="Please log in to view your profile" icon="🔒" />
            </div>
        );
    }

    return (
        <div className="page container">
            <PageHeader 
                title="My Profile" 
                backLink="/" 
                backText="← Back to Home"
                apiLabel="API: GET /api/v1/users/profile"
            />

            {/* Loading State */}
            {loading && <LoadingState message="Loading profile..." />}

            {/* Error State */}
            {!loading && error && (
                <ApiError
                    error={error}
                    endpoint="GET /api/v1/users/profile"
                    onRetry={() => mutate()}
                />
            )}

            {/* Profile Content */}
            {!loading && !error && profile && (
                <div className="card profile-card">
                    {!editMode ? (
                        <div className="profile-view">
                            <div className="profile-field">
                                <label>User ID</label>
                                <span>{profile.id || 'N/A'}</span>
                            </div>
                            <div className="profile-field">
                                <label>Username</label>
                                <span>{profile.username || 'N/A'}</span>
                            </div>
                            <div className="profile-field">
                                <label>Email</label>
                                <span>{profile.email || 'N/A'}</span>
                            </div>
                            <div className="profile-field">
                                <label>Name</label>
                                <span>{profile.name || 'Not set'}</span>
                            </div>
                            <div className="profile-field">
                                <label>Phone</label>
                                <span>{profile.phone || 'Not set'}</span>
                            </div>

                            <button 
                                className="primary"
                                onClick={() => setEditMode(true)}
                            >
                                Edit Profile
                            </button>
                        </div>
                    ) : (
                        <form onSubmit={handleSubmit} className="profile-form">
                            <div className="form-group">
                                <label htmlFor="name">Name</label>
                                <input
                                    type="text"
                                    id="name"
                                    name="name"
                                    value={formData.name}
                                    onChange={handleInputChange}
                                    placeholder="Enter your full name"
                                />
                            </div>

                            <div className="form-group">
                                <label htmlFor="phone">Phone</label>
                                <input
                                    type="tel"
                                    id="phone"
                                    name="phone"
                                    value={formData.phone}
                                    onChange={handleInputChange}
                                    placeholder="Enter your phone number"
                                />
                            </div>

                            <div className="profile-actions">
                                <button 
                                    type="button" 
                                    onClick={handleCancel}
                                    disabled={saving}
                                >
                                    Cancel
                                </button>
                                <button 
                                    type="submit" 
                                    className="primary"
                                    disabled={saving}
                                >
                                    {saving ? 'Saving...' : 'Save Changes'}
                                </button>
                            </div>
                        </form>
                    )}
                </div>
            )}

            {/* API Debug */}
            <ApiDebug data={profile} />
        </div>
    );
}
