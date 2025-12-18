#!/usr/bin/env python3
"""
Luma Helmet - Random Forest Classifier Training Script

Trains a Random Forest model to classify cycling events (brake, crash, normal, bump, turn)
from 3-second windows of MPU6500 IMU data.

Usage:
    python train_classifier.py --data data/labeled_events.csv --output models/rf_classifier.pkl

Author: Sophie Britz
Date: October 2025
"""

import argparse
import sys
from pathlib import Path
import warnings

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split, GridSearchCV
from sklearn.preprocessing import MinMaxScaler
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
    accuracy_score,
    f1_score
)
import matplotlib.pyplot as plt
import seaborn as sns
import joblib

warnings.filterwarnings('ignore')

# ===== CONFIGURATION =====
RANDOM_STATE = 42
TEST_SIZE = 0.2
EVENT_WINDOW_SIZE = 150  # 3 seconds @ 50Hz

# Random Forest Hyperparameters (from report: 77.8% accuracy)
RF_PARAMS = {
    'n_estimators': 200,
    'max_depth': 10,
    'min_samples_split': 2,
    'min_samples_leaf': 1,
    'random_state': RANDOM_STATE,
    'n_jobs': -1  # Use all CPU cores
}


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description='Train Random Forest classifier for Luma helmet event detection'
    )
    parser.add_argument(
        '--data',
        type=str,
        required=True,
        help='Path to labeled events CSV file (from InfluxDB export)'
    )
    parser.add_argument(
        '--output',
        type=str,
        default='models/rf_classifier.pkl',
        help='Output path for trained model (default: models/rf_classifier.pkl)'
    )
    parser.add_argument(
        '--grid-search',
        action='store_true',
        help='Perform grid search for hyperparameter tuning (slower)'
    )
    parser.add_argument(
        '--plot',
        action='store_true',
        help='Generate visualization plots (confusion matrix, feature importance)'
    )
    return parser.parse_args()


def load_and_validate_data(csv_path):
    """Load labeled events from InfluxDB CSV export."""
    print(f"📂 Loading data from: {csv_path}")
    
    df = pd.read_csv(csv_path)
    print(f"✓ Loaded {len(df)} events")
    
    # Validate required columns
    required_cols = ['event_id', 'label', 'accel_x', 'accel_y', 'accel_z', 
                     'gyro_x', 'gyro_y', 'gyro_z']
    missing = set(required_cols) - set(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {missing}")
    
    # Filter out unlabeled or unknown events
    df = df[df['label'].notna()]
    df = df[df['label'] != 'unknown']
    
    print(f"✓ Class distribution:")
    print(df['label'].value_counts())
    
    return df


def engineer_features(df):
    """
    Extract statistical features from 3-second IMU windows.
    
    Based on report's top 20 features:
    - Accelerometer statistics (mean, std, max, min, range, median, skew, kurtosis)
    - Gyroscope statistics
    - Derived metrics (jerk, signal energy, zero-crossing rate)
    """
    print("\n🔧 Engineering features...")
    
    features_list = []
    labels_list = []
    
    for event_id, event_df in df.groupby('event_id'):
        if len(event_df) < EVENT_WINDOW_SIZE:
            continue  # Skip incomplete windows
        
        # Trim to exactly 150 samples
        event_df = event_df.iloc[:EVENT_WINDOW_SIZE]
        
        features = {}
        
        # --- Accelerometer Features ---
        for axis in ['x', 'y', 'z']:
            col = f'accel_{axis}'
            features[f'{col}_mean'] = event_df[col].mean()
            features[f'{col}_std'] = event_df[col].std()
            features[f'{col}_max'] = event_df[col].max()
            features[f'{col}_min'] = event_df[col].min()
            features[f'{col}_range'] = features[f'{col}_max'] - features[f'{col}_min']
            features[f'{col}_median'] = event_df[col].median()
            features[f'{col}_skew'] = event_df[col].skew()
            features[f'{col}_kurtosis'] = event_df[col].kurtosis()
        
        # Acceleration magnitude
        accel_mag = np.sqrt(event_df['accel_x']**2 + event_df['accel_y']**2 + event_df['accel_z']**2)
        features['accel_mag_mean'] = accel_mag.mean()
        features['accel_mag_std'] = accel_mag.std()
        features['accel_mag_max'] = accel_mag.max()
        features['accel_mag_range'] = accel_mag.max() - accel_mag.min()
        
        # --- Gyroscope Features ---
        for axis in ['x', 'y', 'z']:
            col = f'gyro_{axis}'
            features[f'{col}_mean'] = event_df[col].mean()
            features[f'{col}_std'] = event_df[col].std()
            features[f'{col}_max'] = event_df[col].max()
            features[f'{col}_range'] = event_df[col].max() - event_df[col].min()
        
        # Gyroscope magnitude
        gyro_mag = np.sqrt(event_df['gyro_x']**2 + event_df['gyro_y']**2 + event_df['gyro_z']**2)
        features['gyro_mag_mean'] = gyro_mag.mean()
        features['gyro_mag_std'] = gyro_mag.std()
        features['gyro_mag_max'] = gyro_mag.max()
        
        # --- Derived Metrics ---
        # Jerk (rate of change of acceleration)
        jerk = np.diff(accel_mag)
        features['jerk_mean'] = np.abs(jerk).mean()
        features['jerk_max'] = np.abs(jerk).max()
        features['jerk_std'] = jerk.std()
        
        # Signal energy
        features['accel_energy'] = np.sum(accel_mag**2)
        features['gyro_energy'] = np.sum(gyro_mag**2)
        
        # Zero-crossing rate (acceleration)
        zero_crossings = np.diff(np.sign(event_df['accel_x'])) != 0
        features['accel_x_zcr'] = zero_crossings.sum() / len(event_df)
        
        features_list.append(features)
        labels_list.append(event_df['label'].iloc[0])
    
    X = pd.DataFrame(features_list)
    y = pd.Series(labels_list)
    
    print(f"✓ Extracted {len(X.columns)} features from {len(X)} events")
    return X, y


def train_random_forest(X_train, y_train, X_test, y_test, grid_search=False):
    """Train Random Forest classifier."""
    print("\n🌲 Training Random Forest...")
    
    if grid_search:
        print("Running grid search for hyperparameter tuning...")
        param_grid = {
            'n_estimators': [100, 200, 300],
            'max_depth': [8, 10, 12],
            'min_samples_split': [2, 5],
            'min_samples_leaf': [1, 2]
        }
        rf = RandomForestClassifier(random_state=RANDOM_STATE, n_jobs=-1)
        clf = GridSearchCV(rf, param_grid, cv=5, scoring='f1_weighted', verbose=1)
        clf.fit(X_train, y_train)
        print(f"✓ Best parameters: {clf.best_params_}")
        model = clf.best_estimator_
    else:
        model = RandomForestClassifier(**RF_PARAMS)
        model.fit(X_train, y_train)
    
    # Evaluate
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    f1_macro = f1_score(y_test, y_pred, average='macro')
    f1_weighted = f1_score(y_test, y_pred, average='weighted')
    
    print(f"\n📊 Model Performance:")
    print(f"Accuracy: {accuracy:.1%}")
    print(f"Macro F1-Score: {f1_macro:.1%}")
    print(f"Weighted F1-Score: {f1_weighted:.1%}")
    
    print(f"\n📋 Classification Report:")
    print(classification_report(y_test, y_pred))
    
    return model, y_pred


def plot_confusion_matrix(y_test, y_pred, class_names, output_dir='models'):
    """Generate and save confusion matrix plot."""
    cm = confusion_matrix(y_test, y_pred, labels=class_names)
    
    plt.figure(figsize=(10, 8))
    sns.heatmap(
        cm,
        annot=True,
        fmt='d',
        cmap='Blues',
        xticklabels=class_names,
        yticklabels=class_names,
        cbar_kws={'label': 'Count'}
    )
    plt.title('Confusion Matrix - Random Forest Classifier', fontsize=14, pad=20)
    plt.ylabel('True Class', fontsize=12)
    plt.xlabel('Predicted Class', fontsize=12)
    plt.tight_layout()
    
    output_path = Path(output_dir) / 'confusion_matrix.png'
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"✓ Saved confusion matrix to: {output_path}")
    plt.close()


def plot_feature_importance(model, feature_names, output_dir='models', top_n=20):
    """Generate and save feature importance plot."""
    importances = model.feature_importances_
    indices = np.argsort(importances)[::-1][:top_n]
    
    plt.figure(figsize=(10, 8))
    colors = ['#FF6B6B' if 'accel' in feature_names[i] else 
              '#4ECDC4' if 'gyro' in feature_names[i] else 
              '#95E1D3' for i in indices]
    
    plt.barh(range(top_n), importances[indices], color=colors)
    plt.yticks(range(top_n), [feature_names[i] for i in indices])
    plt.xlabel('Feature Importance', fontsize=12)
    plt.title(f'Top {top_n} Most Important Features', fontsize=14, pad=20)
    plt.gca().invert_yaxis()
    
    # Add legend
    from matplotlib.patches import Patch
    legend_elements = [
        Patch(facecolor='#FF6B6B', label='Accelerometer'),
        Patch(facecolor='#4ECDC4', label='Gyroscope'),
        Patch(facecolor='#95E1D3', label='Derived')
    ]
    plt.legend(handles=legend_elements, loc='lower right')
    
    plt.tight_layout()
    output_path = Path(output_dir) / 'feature_importance.png'
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"✓ Saved feature importance to: {output_path}")
    plt.close()


def main():
    args = parse_args()
    
    print("=" * 60)
    print("Luma Helmet - Random Forest Training")
    print("=" * 60)
    
    # Load data
    df = load_and_validate_data(args.data)
    
    # Engineer features
    X, y = engineer_features(df)
    
    # Scale features (MinMaxScaler preserves extreme values for crash detection)
    print("\n⚖️  Scaling features (MinMaxScaler)...")
    scaler = MinMaxScaler()
    X_scaled = pd.DataFrame(
        scaler.fit_transform(X),
        columns=X.columns,
        index=X.index
    )
    
    # Train/test split (stratified to preserve class distribution)
    print(f"\n✂️  Splitting data (test_size={TEST_SIZE}, stratified)...")
    X_train, X_test, y_train, y_test = train_test_split(
        X_scaled, y,
        test_size=TEST_SIZE,
        random_state=RANDOM_STATE,
        stratify=y
    )
    print(f"Training set: {len(X_train)} events")
    print(f"Test set: {len(X_test)} events")
    
    # Train model
    model, y_pred = train_random_forest(
        X_train, y_train, X_test, y_test,
        grid_search=args.grid_search
    )
    
    # Save model and scaler
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    joblib.dump(model, output_path)
    scaler_path = output_path.parent / f"{output_path.stem}_scaler.pkl"
    joblib.dump(scaler, scaler_path)
    
    print(f"\n💾 Saved model to: {output_path}")
    print(f"💾 Saved scaler to: {scaler_path}")
    
    # Generate plots
    if args.plot:
        print("\n📈 Generating visualizations...")
        plot_confusion_matrix(y_test, y_pred, model.classes_, output_path.parent)
        plot_feature_importance(model, X.columns, output_path.parent)
    
    print("\n✅ Training complete!")
    print("=" * 60)


if __name__ == '__main__':
    main()
