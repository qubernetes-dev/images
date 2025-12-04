from importlib.metadata import metadata
import json


def get_python_versions_from_classifiers(package_name: str):
    meta = metadata(package_name)
    classifiers = meta.get_all("Classifier") or []
    versions = []
    for c in classifiers:
        if c.startswith("Programming Language :: Python ::"):
            parts = [p.strip() for p in c.split("::")]
            if len(parts) == 3 and parts[-1][0].isdigit():
                versions.append(parts[-1])
    return sorted(set(versions))


versions = get_python_versions_from_classifiers("cuquantum-python-cu12")

print(json.dumps(versions))
