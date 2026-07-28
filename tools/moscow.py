import matplotlib.pyplot as plt
import numpy as np


def plot_impact_effort(features: list[dict]):
    """Generates an Impact vs. Effort matrix plot for product features.

    Args:
        features: List of dicts with keys 'featureName' (str),
                 'impact' (int 0-10), and 'effort' (int in man-days).
    """
    f = plt.figure()
    f.clear()
    if not features:
        print("No features provided to plot.")
        return

    # Extract data
    names = [f["featureName"] for f in features]
    impacts = [f["impact"] for f in features]
    efforts = [f["effort"] for f in features]

    # Calculate plot bounds
    max_effort = max(efforts) if efforts else 10
    x_max = max(max_effort * 1.15, 5)  # 15% padding on x-axis
    y_max = 10.5

    # Midpoints for quadrant split
    x_mid = max_effort / 2 if max_effort > 0 else 5
    y_mid = 5.0

    # Set up figure
    fig, ax = plt.subplots(figsize=(10, 7), dpi=120)

    # 1. Background Quadrant Colors
    # Top-Left: Quick Wins (High Impact, Low Effort)
    ax.fill_between(
        [0, x_mid], y_mid, y_max, color="#e6f4ea", alpha=0.6, zorder=1
    )
    # Top-Right: Major Projects (High Impact, High Effort)
    ax.fill_between(
        [x_mid, x_max], y_mid, y_max, color="#e8f0fe", alpha=0.6, zorder=1
    )
    # Bottom-Left: Fill-Ins / Small Wins (Low Impact, Low Effort)
    ax.fill_between(
        [0, x_mid], 0, y_mid, color="#f1f3f4", alpha=0.6, zorder=1
    )
    # Bottom-Right: Thankless Tasks / Time Sinks (Low Impact, High Effort)
    ax.fill_between(
        [x_mid, x_max], 0, y_mid, color="#fce8e6", alpha=0.6, zorder=1
    )

    # 2. Quadrant Labels
    ax.text(
        x_mid * 0.05,
        y_max - 0.5,
        "QUICK WINS\n(High Impact, Low Effort)",
        fontsize=10,
        fontweight="bold",
        color="#137333",
        va="top",
    )
    ax.text(
        x_max - (x_mid * 0.05),
        y_max - 0.5,
        "MAJOR PROJECTS\n(High Impact, High Effort)",
        fontsize=10,
        fontweight="bold",
        color="#1a73e8",
        va="top",
        ha="right",
    )
    ax.text(
        x_mid * 0.05,
        0.5,
        "FILL-INS / SMALL WINS\n(Low Impact, Low Effort)",
        fontsize=10,
        fontweight="bold",
        color="#5f6368",
        va="bottom",
    )
    ax.text(
        x_max - (x_mid * 0.05),
        0.5,
        "THANKLESS TASKS\n(Low Impact, High Effort)",
        fontsize=10,
        fontweight="bold",
        color="#c5221f",
        va="bottom",
        ha="right",
    )

    # 3. Quadrant Dividing Lines
    ax.axhline(y_mid, color="#bdc1c6", linestyle="--", linewidth=1.2, zorder=2)
    ax.axvline(x_mid, color="#bdc1c6", linestyle="--", linewidth=1.2, zorder=2)

    # 4. Scatter Plot Points
    scatter = ax.scatter(
        efforts,
        impacts,
        color="#1a73e8",
        s=120,
        edgecolors="white",
        linewidth=1.5,
        zorder=4,
    )

    # 5. Feature Labels with offset
    for i, name in enumerate(names):
        ax.annotate(
            name,
            (efforts[i], impacts[i]),
            xytext=(7, 5),
            textcoords="offset points",
            fontsize=9,
            fontweight="semibold",
            color="#202124",
            bbox=dict(
                boxstyle="round,pad=0.2",
                facecolor="white",
                edgecolor="none",
                alpha=0.7,
            ),
            zorder=5,
        )

    # 6. Axis Limits & Styling
    ax.set_xlim(0, x_max)
    ax.set_ylim(0, y_max)

    ax.set_xlabel("Effort (Man-Days)", fontsize=11, fontweight="bold", labelpad=10)
    ax.set_ylabel("Impact (0 to 10)", fontsize=11, fontweight="bold", labelpad=10)
    ax.set_title(
        "Feature Prioritization Matrix (Impact vs. Effort)",
        fontsize=14,
        fontweight="bold",
        pad=15,
    )

    # Clean up grid & spines
    ax.set_axisbelow(True)
    ax.grid(True, linestyle=":", alpha=0.5, zorder=2)
    for spine in ["top", "right"]:
        ax.spines[spine].set_visible(False)

    plt.tight_layout()
    plt.savefig("moscowplot.png")
    plt.close(f)


# Example Usage
if __name__ == "__main__":
    data = [
        {"featureName": "data ingestion PL", "impact": 7, "effort": 10},
        {"featureName": "CDK infra", "impact": 9, "effort": 5},
        {"featureName": "user interface base", "impact": 9, "effort": 7},
        {"featureName": "k means", "impact": 8, "effort": 10},
        {"featureName": "k means cross analysis", "impact": 8, "effort": 6},
        {"featureName": "UI APIs", "impact": 10, "effort": 5},
        {"featureName": "XY charts", "impact": 4, "effort": 5},
        {"featureName": "Graph relationships", "impact": 3, "effort": 10},
        {"featureName": "UI guide buttons", "impact": 3, "effort": 2},
        {"featureName": "Map Projections", "impact": 8, "effort": 3},
    ]

    plot_impact_effort(data)