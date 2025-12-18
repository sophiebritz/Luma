#!/usr/bin/env python3
"""
Luma Smart Helmet - Random Forest Classifier Training
======================================================
Trains a Random Forest classifier for cycling event detection (brake, crash, normal, bump, turn)
Exports model parameters for ESP32 deployment
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split, GridSearchCV, cross_val_score, StratifiedKFold
from sklearn.preprocessing import MinMaxScaler, LabelEncoder
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score, f1_score
import json
import pickle
import warnings
warnings.filterwarnings('ignore')

# ===== Configuration =====
RANDOM_STATE = 42
TEST_SIZE = 0.2
SAMPLE_RATE = 50  # Hz
WINDOW_SIZE = 150  # 3 seconds at 50Hz

# ===== Load Data =====
print("=" * 60)
print("LUMA SMART HELMET - RANDOM FOREST CLASSIFIER TRAINING")
print("=" * 60)

# Load labeled events CSV
df = pd.read_csv('influxdata_2025-12-15T15_26_28Z.csv', skiprows=3)
df = df.drop(columns=['Unnamed: 0'], errors='ignore')

# Load metadata
metadata_df = pd.read_csv('influxdata_2025-12-15T15_26_51Z.csv', skiprows=3)

print(f"\n[1] DATA LOADING")
print(f"    Total samples: {len(df):,}")
print(f"    Unique events: {df['event_id'].nunique()}")

# Filter out unknown labels
df = df[df['label'] != 'unknown']
print(f"    Samples after filtering unknown: {len(df):,}")

# ===== Feature Engineering per Event Window =====
print(f"\n[2] FEATURE ENGINEERING")

def extract_features(group):
    """Extract statistical features from a 3-second event window"""
    features = {}
    
    # Accelerometer features
    for axis in ['accel_x', 'accel_y', 'accel_z', 'accel_mag']:
        features[f'{axis}_mean'] = group[axis].mean()
        features[f'{axis}_std'] = group[axis].std()
        features[f'{axis}_max'] = group[axis].max()
        features[f'{axis}_min'] = group[axis].min()
        features[f'{axis}_range'] = group[axis].max() - group[axis].min()
        features[f'{axis}_median'] = group[axis].median()
        features[f'{axis}_skew'] = group[axis].skew()
        features[f'{axis}_kurtosis'] = group[axis].kurtosis()
    
    # Gyroscope features
    for axis in ['gyro_x', 'gyro_y', 'gyro_z']:
        features[f'{axis}_mean'] = group[axis].mean()
        features[f'{axis}_std'] = group[axis].std()
        features[f'{axis}_max'] = group[axis].max()
        features[f'{axis}_min'] = group[axis].min()
        features[f'{axis}_range'] = group[axis].max() - group[axis].min()
        features[f'{axis}_abs_max'] = group[axis].abs().max()
    
    # Derived features
    features['gyro_mag_mean'] = np.sqrt(group['gyro_x']**2 + group['gyro_y']**2 + group['gyro_z']**2).mean()
    features['gyro_mag_max'] = np.sqrt(group['gyro_x']**2 + group['gyro_y']**2 + group['gyro_z']**2).max()
    
    # Jerk (rate of change of acceleration)
    if len(group) > 1:
        dt = 1 / SAMPLE_RATE
        jerk = np.diff(group['accel_mag'].values) / dt
        features['jerk_mean'] = np.mean(np.abs(jerk))
        features['jerk_max'] = np.max(np.abs(jerk))
        features['jerk_std'] = np.std(jerk)
    else:
        features['jerk_mean'] = 0
        features['jerk_max'] = 0
        features['jerk_std'] = 0
    
    # Signal energy
    features['accel_energy'] = np.sum(group['accel_mag']**2) / len(group)
    features['gyro_energy'] = np.sum(group['gyro_x']**2 + group['gyro_y']**2 + group['gyro_z']**2) / len(group)
    
    # Zero crossing rate for gyro (indicates direction changes)
    for axis in ['gyro_x', 'gyro_y', 'gyro_z']:
        signal = group[axis].values - group[axis].mean()
        features[f'{axis}_zcr'] = np.sum(np.abs(np.diff(np.sign(signal)))) / (2 * len(signal))
    
    # Peak analysis
    accel_peak_idx = group['accel_mag'].idxmax()
    features['peak_position'] = (group.index.get_loc(accel_peak_idx) / len(group)) if accel_peak_idx in group.index else 0.5
    
    # Label
    features['label'] = group['label'].iloc[0]
    features['event_id'] = group['event_id'].iloc[0]
    
    return pd.Series(features)

# Group by event and extract features
print("    Extracting features from event windows...")
event_features = df.groupby('event_id').apply(extract_features).reset_index(drop=True)
print(f"    Features extracted: {len(event_features.columns) - 2} features per event")
print(f"    Total events: {len(event_features)}")

# ===== Class Distribution =====
print(f"\n[3] CLASS DISTRIBUTION")
class_dist = event_features['label'].value_counts()
print("\n    Class       Count    Percentage")
print("    " + "-" * 35)
for label, count in class_dist.items():
    pct = count / len(event_features) * 100
    print(f"    {label:<10}  {count:>5}    {pct:>6.1f}%")

# ===== Prepare Data for Training =====
print(f"\n[4] DATA PREPARATION")

feature_cols = [c for c in event_features.columns if c not in ['label', 'event_id']]
X = event_features[feature_cols].values
y = event_features['label'].values

# Encode labels
le = LabelEncoder()
y_encoded = le.fit_transform(y)
print(f"    Classes: {list(le.classes_)}")
print(f"    Class encoding: {dict(zip(le.classes_, range(len(le.classes_))))}")

# Scale features using MinMaxScaler (preserves outliers better for crash detection)
scaler = MinMaxScaler()
X_scaled = scaler.fit_transform(X)

# Train/test split with stratification
X_train, X_test, y_train, y_test = train_test_split(
    X_scaled, y_encoded, test_size=TEST_SIZE, random_state=RANDOM_STATE, stratify=y_encoded
)
print(f"    Training samples: {len(X_train)}")
print(f"    Test samples: {len(X_test)}")

# ===== Hyperparameter Tuning =====
print(f"\n[5] HYPERPARAMETER TUNING (Grid Search)")

param_grid = {
    'n_estimators': [50, 100, 200],
    'max_depth': [10, 20, 30, None],
    'min_samples_split': [2, 5, 10],
    'min_samples_leaf': [1, 2, 4]
}

rf_base = RandomForestClassifier(random_state=RANDOM_STATE, n_jobs=-1)
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE)

grid_search = GridSearchCV(
    rf_base, param_grid, cv=cv, scoring='f1_macro', n_jobs=-1, verbose=0
)
print("    Running grid search (this may take a moment)...")
grid_search.fit(X_train, y_train)

print(f"\n    Best Parameters:")
for param, value in grid_search.best_params_.items():
    print(f"      {param}: {value}")
print(f"    Best CV F1-Score: {grid_search.best_score_:.4f}")

# ===== Train Final Model =====
print(f"\n[6] TRAINING FINAL MODEL")

best_params = grid_search.best_params_
rf_model = RandomForestClassifier(**best_params, random_state=RANDOM_STATE, n_jobs=-1)
rf_model.fit(X_train, y_train)

# Cross-validation scores
cv_scores = cross_val_score(rf_model, X_scaled, y_encoded, cv=5, scoring='f1_macro')
print(f"    5-Fold CV F1-Score: {cv_scores.mean():.4f} (+/- {cv_scores.std()*2:.4f})")

# ===== Model Evaluation =====
print(f"\n[7] MODEL EVALUATION")

y_pred = rf_model.predict(X_test)

print("\n    CLASSIFICATION REPORT")
print("    " + "=" * 55)
report = classification_report(y_test, y_pred, target_names=le.classes_, output_dict=True)
print(f"\n    {'Class':<10} {'Precision':>10} {'Recall':>10} {'F1-Score':>10} {'Support':>10}")
print("    " + "-" * 55)
for cls in le.classes_:
    r = report[cls]
    print(f"    {cls:<10} {r['precision']:>10.3f} {r['recall']:>10.3f} {r['f1-score']:>10.3f} {int(r['support']):>10}")
print("    " + "-" * 55)
print(f"    {'Accuracy':<10} {'':<10} {'':<10} {report['accuracy']:>10.3f} {int(report['macro avg']['support']):>10}")
print(f"    {'Macro Avg':<10} {report['macro avg']['precision']:>10.3f} {report['macro avg']['recall']:>10.3f} {report['macro avg']['f1-score']:>10.3f}")
print(f"    {'Weighted':<10} {report['weighted avg']['precision']:>10.3f} {report['weighted avg']['recall']:>10.3f} {report['weighted avg']['f1-score']:>10.3f}")

# Confusion Matrix
print("\n    CONFUSION MATRIX")
print("    " + "=" * 55)
cm = confusion_matrix(y_test, y_pred)
print(f"\n    {'Predicted →':<12}", end="")
for cls in le.classes_:
    print(f"{cls[:6]:>8}", end="")
print("\n    Actual ↓")
print("    " + "-" * 55)
for i, cls in enumerate(le.classes_):
    print(f"    {cls:<12}", end="")
    for j in range(len(le.classes_)):
        print(f"{cm[i,j]:>8}", end="")
    print()

# ===== Feature Importance =====
print(f"\n[8] FEATURE IMPORTANCE (Top 20)")
print("    " + "=" * 55)

importances = rf_model.feature_importances_
indices = np.argsort(importances)[::-1]

print(f"\n    {'Rank':<6} {'Feature':<30} {'Importance':>12}")
print("    " + "-" * 55)
for rank, idx in enumerate(indices[:20], 1):
    print(f"    {rank:<6} {feature_cols[idx]:<30} {importances[idx]:>12.4f}")

# ===== Export for ESP32 =====
print(f"\n[9] EXPORTING MODEL FOR ESP32")

# Export simplified model parameters
# For ESP32 deployment, we'll export a decision tree ensemble representation
export_data = {
    'model_type': 'RandomForest',
    'n_estimators': best_params['n_estimators'],
    'max_depth': best_params['max_depth'],
    'classes': list(le.classes_),
    'class_encoding': {cls: int(idx) for idx, cls in enumerate(le.classes_)},
    'n_features': len(feature_cols),
    'feature_names': feature_cols,
    'scaler_min': scaler.data_min_.tolist(),
    'scaler_max': scaler.data_max_.tolist(),
    'accuracy': float(report['accuracy']),
    'f1_macro': float(report['macro avg']['f1-score'])
}

with open('model_config.json', 'w') as f:
    json.dump(export_data, f, indent=2)
print("    Saved: model_config.json")

# Save full model
with open('rf_model.pkl', 'wb') as f:
    pickle.dump({
        'model': rf_model,
        'scaler': scaler,
        'label_encoder': le,
        'feature_names': feature_cols
    }, f)
print("    Saved: rf_model.pkl")

# Export feature extraction code for ESP32
esp32_features = """
// Feature indices for ESP32 classifier
// Generated automatically from training script

#ifndef FEATURE_INDICES_H
#define FEATURE_INDICES_H

// Number of features
#define N_FEATURES {n_features}

// Class definitions
{class_defines}

// Feature scaling parameters (MinMax)
const float FEATURE_MIN[{n_features}] = {{{min_vals}}};
const float FEATURE_MAX[{n_features}] = {{{max_vals}}};

// Feature names (for debugging)
const char* FEATURE_NAMES[{n_features}] = {{
{feature_names}
}};

#endif
""".format(
    n_features=len(feature_cols),
    class_defines='\n'.join([f'#define CLASS_{cls.upper()} {i}' for i, cls in enumerate(le.classes_)]),
    min_vals=', '.join([f'{v:.6f}f' for v in scaler.data_min_]),
    max_vals=', '.join([f'{v:.6f}f' for v in scaler.data_max_]),
    feature_names=',\n'.join([f'    "{name}"' for name in feature_cols])
)

with open('feature_indices.h', 'w') as f:
    f.write(esp32_features)
print("    Saved: feature_indices.h")

# ===== Export Decision Rules for ESP32 =====
# Since full RF can be large, export a simplified decision tree
from sklearn.tree import export_text, DecisionTreeClassifier

# Train a simpler model for ESP32
dt_simple = DecisionTreeClassifier(max_depth=10, random_state=RANDOM_STATE)
dt_simple.fit(X_train, y_train)
dt_acc = accuracy_score(y_test, dt_simple.predict(X_test))

print(f"\n    Simplified Decision Tree Accuracy: {dt_acc:.4f}")

# Export decision tree rules as C code
def tree_to_c_code(tree, feature_names, class_names):
    tree_ = tree.tree_
    feature_name = [
        feature_names[i] if i >= 0 else "undefined"
        for i in tree_.feature
    ]
    
    lines = []
    lines.append("// Auto-generated decision tree classifier")
    lines.append("// Accuracy: {:.4f}".format(dt_acc))
    lines.append("")
    lines.append("int classify_event(float* features) {")
    
    def recurse(node, depth):
        indent = "    " * (depth + 1)
        if tree_.feature[node] >= 0:
            name = f"features[{tree_.feature[node]}]"
            threshold = tree_.threshold[node]
            lines.append(f"{indent}if ({name} <= {threshold:.6f}f) {{")
            recurse(tree_.children_left[node], depth + 1)
            lines.append(f"{indent}}} else {{")
            recurse(tree_.children_right[node], depth + 1)
            lines.append(f"{indent}}}")
        else:
            class_idx = np.argmax(tree_.value[node])
            lines.append(f"{indent}return {class_idx}; // {class_names[class_idx]}")
    
    recurse(0, 0)
    lines.append("}")
    return '\n'.join(lines)

c_code = tree_to_c_code(dt_simple, feature_cols, le.classes_)
with open('classifier_tree.c', 'w') as f:
    f.write(c_code)
print("    Saved: classifier_tree.c")

# ===== Summary Statistics =====
print(f"\n[10] SUMMARY")
print("=" * 60)
print(f"    Model: Random Forest ({best_params['n_estimators']} trees)")
print(f"    Features: {len(feature_cols)}")
print(f"    Classes: {len(le.classes_)} ({', '.join(le.classes_)})")
print(f"    Test Accuracy: {report['accuracy']:.2%}")
print(f"    Macro F1-Score: {report['macro avg']['f1-score']:.4f}")
print(f"    Simplified DT Accuracy: {dt_acc:.2%}")
print("=" * 60)

# ===== Save Classification Report as Table =====
report_df = pd.DataFrame(report).transpose()
report_df.to_csv('classification_report.csv')
print("\n    Saved: classification_report.csv")

# Save confusion matrix
cm_df = pd.DataFrame(cm, index=le.classes_, columns=le.classes_)
cm_df.to_csv('confusion_matrix.csv')
print("    Saved: confusion_matrix.csv")

# Save feature importance
fi_df = pd.DataFrame({
    'Feature': feature_cols,
    'Importance': importances
}).sort_values('Importance', ascending=False)
fi_df.to_csv('feature_importance.csv', index=False)
print("    Saved: feature_importance.csv")

print("\n✓ Training complete! All files exported.")
