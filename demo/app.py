"""Gradio tour UI — digital prototype only."""

from __future__ import annotations

from models.optimizer import optimize_pattern
from models.renderer import apply_pattern_to_scene, dual_band_preview
from models.scenes import SITE_CLASSES, generate_scene
from PIL import Image


def _run(site_class: str, steps: int, seed: int):
    res = optimize_pattern(site_class, seed=int(seed), steps=int(steps), size=256)
    scene = generate_scene(site_class, seed=int(seed), size=256)
    covered = apply_pattern_to_scene(scene, res.pattern_rgb, res.pattern_emis)
    vis_b, ir_b = dual_band_preview(scene)
    vis_a, ir_a = dual_band_preview(covered)
    tile = Image.fromarray(res.pattern_rgb)
    collapse = (res.baseline_score - res.best_score) / max(res.baseline_score, 1e-6)
    note = (
        f"Digital surrogate only — not field effectiveness. "
        f"baseline={res.baseline_score:.3f} covered={res.best_score:.3f} "
        f"collapse={collapse:.3f}. Mantle ≠ Veil ≠ MPL-D."
    )
    return vis_b, vis_a, ir_b, ir_a, tile, note


def build_ui():
    import gradio as gr

    with gr.Blocks(title="MS-C Mantle") as demo:
        gr.Markdown(
            "# MS-C Mantle — digital prototype\n"
            "**Passive site camo** beside MPL-D (dazzle) and MS-V Veil (obscurant). "
            "Not a laser. Not validated in the field."
        )
        with gr.Row():
            site = gr.Dropdown(list(SITE_CLASSES), value="substation", label="Site class")
            steps = gr.Slider(5, 80, value=25, step=1, label="Optimize steps")
            seed = gr.Number(value=7, precision=0, label="Seed")
        btn = gr.Button("Generate kit preview")
        with gr.Row():
            vis_b = gr.Image(label="VIS uncovered")
            vis_a = gr.Image(label="VIS Mantle")
        with gr.Row():
            ir_b = gr.Image(label="LWIR proxy uncovered")
            ir_a = gr.Image(label="LWIR proxy Mantle")
        tile = gr.Image(label="Manufacturable tile")
        note = gr.Textbox(label="Score (surrogate)")
        btn.click(_run, [site, steps, seed], [vis_b, vis_a, ir_b, ir_a, tile, note])
    return demo


def main() -> None:
    demo = build_ui()
    demo.launch()


if __name__ == "__main__":
    main()
