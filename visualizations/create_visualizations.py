"""
=================================================================
FRAUD DETECTION - DATA VISUALIZATIONS
=================================================================
Author: Luiz Milaré
Date: February 2026
Description: Generate professional visualizations for fraud analysis
Requirements: pandas, matplotlib, seaborn, sqlalchemy, pymysql
=================================================================
"""
from config import MYSQL_PASSWORD
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from sqlalchemy import create_engine
import warnings
warnings.filterwarnings('ignore')

# Set style for professional-looking plots
plt.style.use('seaborn-v0_8-darkgrid')
sns.set_palette("husl")

print("=" * 70)
print("📊 CREATING FRAUD DETECTION VISUALIZATIONS")
print("=" * 70)

# =================================================================
# STEP 1: CONNECT TO DATABASE
# =================================================================
print("\n🔗 Connecting to MySQL database...")

# CHANGE THIS: Your MySQL password
mysql_password = MYSQL_PASSWORD  
database_name = 'fraud_detection'

engine = create_engine(
    f'mysql+pymysql://root:{mysql_password}@localhost/{database_name}'
)

print("✅ Connected successfully!")

# =================================================================
# STEP 2: LOAD DATA
# =================================================================
print("\n📥 Loading hourly fraud data...")

# SQL query - same as Query 5
query = """
WITH hourly_transactions AS (
    SELECT 
        FLOOR(time_seconds / 3600) AS hour_sequence,
        hour_of_day,
        FLOOR(time_seconds / 86400) AS day_number,
        SUM(is_fraud) AS total_frauds,
        ROUND((SUM(is_fraud) / COUNT(*)) * 100, 2) AS fraud_rate_pct
    FROM transactions
    GROUP BY hour_sequence, hour_of_day, day_number
)
SELECT 
    hour_sequence,
    day_number,
    hour_of_day,
    total_frauds,
    fraud_rate_pct
FROM hourly_transactions
ORDER BY hour_sequence;
"""

# Execute query and load into pandas DataFrame
df = pd.read_sql(query, engine)

print(f"✅ Data loaded: {len(df)} hours")
print("\nFirst 5 rows:")
print(df.head())

# =================================================================
# STEP 3: CREATE VISUALIZATION 1 - Fraud Rate Timeline
# =================================================================
print("\n🎨 Creating visualization...")

# Create figure and axis
fig, ax = plt.subplots(figsize=(14, 6))

# Plot the fraud rate line
ax.plot(
    df['hour_sequence'],      # X axis: hours (0 to 47)
    df['fraud_rate_pct'],     # Y axis: fraud rate percentage
    linewidth=2.5,            # Line thickness
    color='#e74c3c',          # Red color
    marker='o',               # Circle markers on each point
    markersize=5,             # Marker size
    label='Fraud Rate (%)'    # Legend label
)

# Highlight spike hours (rate > 1.0%)
spikes = df[df['fraud_rate_pct'] > 1.0]
ax.scatter(
    spikes['hour_sequence'],  # X positions of spikes
    spikes['fraud_rate_pct'], # Y positions of spikes
    color='darkred',          # Darker red for emphasis
    s=200,                    # Size of markers
    zorder=5,                 # Draw on top of line
    label='Spike (>1.0%)',    # Legend label
    edgecolors='black',       # Black border around markers
    linewidths=2
)

# Add average line
avg_rate = df['fraud_rate_pct'].mean()
ax.axhline(
    y=avg_rate,               # Y position (the average)
    color='gray',             # Gray color
    linestyle='--',           # Dashed line
    linewidth=2,              # Line thickness
    label=f'Average ({avg_rate:.2f}%)'  # Label with value
)

# Add vertical line between Day 0 and Day 1
ax.axvline(
    x=23.5,                   # Between hour 23 and 24
    color='blue',             # Blue color
    linestyle=':',            # Dotted line
    linewidth=2,              # Line thickness
    alpha=0.6,                # Transparency (0=invisible, 1=solid)
    label='Day 2 Start'       # Legend label
)

# Labels and title
ax.set_xlabel('Hour Sequence (0-47)', fontsize=12, fontweight='bold')
ax.set_ylabel('Fraud Rate (%)', fontsize=12, fontweight='bold')
ax.set_title(
    'Fraud Rate Evolution Over 48 Hours', 
    fontsize=16, 
    fontweight='bold',
    pad=20  # Space above title
)

# Add legend
ax.legend(loc='upper right', fontsize=11, framealpha=0.9)

# Add grid for readability
ax.grid(True, alpha=0.3, linestyle='-', linewidth=0.5)

# Adjust layout to prevent cutting off labels
plt.tight_layout()

# Save the figure
output_path = 'visualizations/images/fraud_rate_timeline.png'
plt.savefig(output_path, dpi=300, bbox_inches='tight')

print(f"✅ Chart saved: {output_path}")
print("\n🎉 Visualization complete!")

# Close the plot to free memory
plt.close()

# =================================================================
# STEP 4: LOAD DATA FOR VISUALIZATION 2
# =================================================================
print("\n📥 Loading amount range data...")

# SQL query - from Query 3
query_amount = """
WITH amount_categories AS (
    SELECT 
        transaction_id,
        amount,
        is_fraud,
        CASE 
            WHEN amount < 10 THEN '€0-10'
            WHEN amount < 50 THEN '€10-50'
            WHEN amount < 100 THEN '€50-100'
            WHEN amount < 200 THEN '€100-200'
            ELSE '€200+'
        END AS amount_range
    FROM transactions
)
SELECT 
    amount_range,
    COUNT(*) AS total_transactions,
    SUM(is_fraud) AS total_frauds,
    ROUND((SUM(is_fraud) / COUNT(*)) * 100, 2) AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END), 2) AS fraud_loss_eur
FROM amount_categories
GROUP BY amount_range
ORDER BY 
    CASE amount_range
        WHEN '€0-10' THEN 1
        WHEN '€10-50' THEN 2
        WHEN '€50-100' THEN 3
        WHEN '€100-200' THEN 4
        ELSE 5
    END;
"""

# Execute query and load into DataFrame
df_amount = pd.read_sql(query_amount, engine)

print(f"✅ Data loaded: {len(df_amount)} amount ranges")
print("\nData preview:")
print(df_amount)

# =================================================================
# STEP 5: CREATE VISUALIZATION 2 - Fraud by Amount Range
# =================================================================
print("\n🎨 Creating second visualization...")

# Create figure with 2 subplots side by side
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

# Define colors for each bar
colors = ['#2ecc71', '#f39c12', '#3498db', '#9b59b6', '#e74c3c']

# =================================================================
# LEFT PLOT: Fraud Rate by Amount Range
# =================================================================

# Create horizontal bar chart
ax1.barh(
    df_amount['amount_range'],     # Y axis: amount ranges
    df_amount['fraud_rate_pct'],   # X axis: fraud rate %
    color=colors,                   # Different color for each bar
    edgecolor='black',              # Black border around bars
    linewidth=1                     # Border thickness
)

# Add percentage labels on bars
for idx, row in df_amount.iterrows():
    ax1.text(
        row['fraud_rate_pct'] + 0.01,  # X position (slightly right of bar)
        idx,                            # Y position (bar index)
        f"{row['fraud_rate_pct']}%",   # Text to show
        va='center',                    # Vertical alignment: center
        fontsize=10,                    # Font size
        fontweight='bold'               # Bold text
    )

# Labels and title
ax1.set_xlabel('Fraud Rate (%)', fontsize=11, fontweight='bold')
ax1.set_ylabel('Transaction Amount Range', fontsize=11, fontweight='bold')
ax1.set_title(
    'Fraud Risk by Amount Range\n(Higher % = More Risky)', 
    fontsize=12, 
    fontweight='bold'
)
ax1.grid(axis='x', alpha=0.3)  # Grid only on X axis

# =================================================================
# RIGHT PLOT: Financial Loss by Amount Range
# =================================================================

# Create horizontal bar chart
ax2.barh(
    df_amount['amount_range'],     # Y axis: amount ranges
    df_amount['fraud_loss_eur'],   # X axis: loss in euros
    color=colors,                   # Same colors as left plot
    edgecolor='black',              # Black border
    linewidth=1                     # Border thickness
)

# Add euro labels on bars
for idx, row in df_amount.iterrows():
    ax2.text(
        row['fraud_loss_eur'] + 1000,      # X position (slightly right)
        idx,                                # Y position
        f"€{row['fraud_loss_eur']:,.0f}",  # Format with comma separator
        va='center',                        # Vertical alignment
        fontsize=10,                        # Font size
        fontweight='bold'                   # Bold text
    )

# Labels and title
ax2.set_xlabel('Total Fraud Loss (€)', fontsize=11, fontweight='bold')
ax2.set_ylabel('Transaction Amount Range', fontsize=11, fontweight='bold')
ax2.set_title(
    'Financial Impact by Amount Range\n(Total Loss in Euros)', 
    fontsize=12, 
    fontweight='bold'
)
ax2.grid(axis='x', alpha=0.3)  # Grid only on X axis

# Adjust layout
plt.tight_layout()

# Save the figure
output_path2 = 'visualizations/images/fraud_by_amount.png'
plt.savefig(output_path2, dpi=300, bbox_inches='tight')

print(f"✅ Chart saved: {output_path2}")
print("\n🎉 All visualizations complete!")

# Close the plot
plt.close()

print("\n" + "=" * 70)
print("✅ SUCCESS! 2 visualizations created:")
print("  1. fraud_rate_timeline.png")
print("  2. fraud_by_amount.png")
print("=" * 70)