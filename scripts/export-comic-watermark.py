"""Export the official SLBR weights to the application's image/clean ONNX contract."""
import argparse
from pathlib import Path
import sys
from types import ModuleType, SimpleNamespace

import torch


def load_network(source):
    for name in ('src', 'src.networks', 'src.utils'):
        package = ModuleType(name)
        package.__path__ = []
        sys.modules[name] = package
    modules = (
        ('src.utils.model_init', 'src/utils/model_init.py'),
        ('src.networks.blocks', 'src/networks/blocks.py'),
        ('src.networks.resunet', 'src/networks/resunet.py'),
    )
    for name, relative in modules:
        path = source / relative
        text = path.read_text(encoding='utf-8')
        # These imports belong to training and visualization; inference uses PyTorch.
        lines = [line for line in text.splitlines() if line.strip() not in
                 ('import torchvision', 'import cv2', 'import scipy.stats as st')]
        module = ModuleType(name)
        module.__file__ = str(path)
        sys.modules[name] = module
        exec(compile('\n'.join(lines), str(path), 'exec'), module.__dict__)
    options = SimpleNamespace(mask_mode='res', bg_mode='res_mask', sim_metric='cos',
                              k_center=2, project_mode='simple', use_refine=True,
                              k_refine=3, k_skip_stage=3)
    return sys.modules['src.networks.resunet'].SLBR(options, shared_depth=1, blocks=3, long_skip=True)


class WatermarkExport(torch.nn.Module):
    def __init__(self, network):
        super().__init__()
        self.network = network

    def forward(self, image):
        backgrounds, masks, _ = self.network(image)
        mask = masks[0]
        return torch.clamp(backgrounds[0] * mask + image * (1 - mask), 0, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    torch.set_num_threads(2)
    network = load_network(args.source)
    checkpoint = torch.load(args.checkpoint, map_location='cpu', weights_only=True)
    state = checkpoint['state_dict']
    network.load_state_dict({key.removeprefix('module.'): tensor for key, tensor in state.items()})
    network.eval()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with torch.inference_mode():
        torch.onnx.export(WatermarkExport(network).eval(), torch.zeros(1, 3, 256, 256),
                          str(args.output), input_names=['image'], output_names=['clean'],
                          opset_version=17, do_constant_folding=True)
    print(args.output)


if __name__ == '__main__':
    main()
