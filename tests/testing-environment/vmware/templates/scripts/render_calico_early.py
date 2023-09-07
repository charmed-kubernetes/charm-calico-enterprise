import jinja2
import json
import argparse

parser = argparse.ArgumentParser("Calico Early Renderer")
parser.add_argument("node_info", dest="node_info", type=str, help="path to json file with node information")

def render_calico_early(args):
    calico_early_template = None

    with open('/tmp/calico_early.tpl','w') as fh:
        calico_early_template = jinja2.Template(fh.read())

    node_info = None

    with open(args.node_info, 'r') as json_file:
        node_info = json.loads(json_file.read())

    # TODO: Any manipulation of node_info before passing to template.

    with open('/calico-early/cfg.yml', 'w') as fh:
        fh.write(calico_early_template.render(**node_info))

    print("Rendered calico early")
    

if __name__ == "__main__":
    args = parser.parse_args()
    render_calico_early(args)