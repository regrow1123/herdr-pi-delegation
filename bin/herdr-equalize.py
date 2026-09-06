#!/usr/bin/env python3
"""herdr 우측 열 등분: 우측 열의 down-split 비율을 leaf 수 기준으로 재조정.

사용법: herdr-equalize.py <tab_id>
  - layout.set_split_ratio 소켓 호출로 우측 열 내부 down-split ratio를 등분으로 설정
  - root 트리 구조에서 leaf(pane) 수를 세어 ratio = first_leaves / total_leaves
"""
import json
import os
import socket
import sys

# HERDR_SOCKET_PATH 우선, 없으면 기본 경로 fallback
SOCKET = os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser("~/.config/herdr/herdr.sock")
TAB = sys.argv[1] if len(sys.argv) > 1 else None


def rpc(method: str, params: dict) -> dict:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect(SOCKET)
    req = {"id": f"eq:{method}:{__import__('time').time_ns()}", "method": method, "params": params}
    s.sendall((json.dumps(req) + "\n").encode())
    data = b""
    while True:
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            break
        if not chunk:
            break
        data += chunk
    s.close()
    return json.loads(data)


def leaf_count(node: dict) -> int:
    """트리 노드의 leaf(pane) 수"""
    if node.get("type") == "pane":
        return 1
    return leaf_count(node["first"]) + leaf_count(node["second"])


def collect_splits(node: dict, path: list, out: list, is_right_column: bool):
    """우측 열 내부의 down-split 노드들 수집 (path, leaf수 포함)"""
    if node.get("type") == "pane":
        return
    if node.get("type") == "split":
        direction = node.get("direction")
        # path = 이 split 노드 자신까지의 경로 (false=first, true=second)
        if is_right_column and direction == "down":
            first_leaves = leaf_count(node["first"])
            second_leaves = leaf_count(node["second"])
            out.append({
                "path": list(path),  # 이 split 노드 자체의 path
                "first_leaves": first_leaves,
                "second_leaves": second_leaves,
                "total": first_leaves + second_leaves,
                "ratio": first_leaves / (first_leaves + second_leaves),
            })
        # 재귀: 자식으로 내려갈 때 경로에 false/true 추가
        # right split의 second가 우측 열, first가 좌측. down split의 자식은 같은 열 상속.
        if direction == "right":
            collect_splits(node["second"], path + [True], out, True)   # second = 우측
            collect_splits(node["first"], path + [False], out, False)  # first = 좌측
        else:  # down
            collect_splits(node["first"], path + [False], out, is_right_column)
            collect_splits(node["second"], path + [True], out, is_right_column)


def main():
    if not TAB:
        print("usage: herdr-equalize.py <tab_id>", file=sys.stderr)
        sys.exit(1)

    # 현재 레이아웃의 root 트리 가져오기 (layout.set_split_ratio에 dummy 호출 or snapshot)
    # 가장 확실: layout.set_split_ratio를 아무 path 없이 호출하면 에러지만 트리는 안 줌 → snapshot 사용
    # 대신: set_split_ratio 응답의 layout.root를 재사용하기 위해 먼저 실제 조회가 필요.
    # layout snapshot API가 있는지: herdr api snapshot이 panes만 줌.
    # → 소켓으로 layout.get (없으면) 대안: 여기서는 기존 set 호출 응답을 못 받으니,
    #   우선 split이 이미 적용된 상태에서 이 스크립트를 실행한다고 가정하고,
    #   root를 얻기 위해 dummy ratio 호출을 쓰지 말고, 아래처럼 직접 트리를 요청.
    # herdr에서 트리를 주는 응답: layout.set_split_ratio (성공 시). 
    # 특정 split path를 1회 변경해 트리를 얻고, 다시 등분 ratio들로 덮어쓰는 방식.

    # 1. root 트리 획득: set_split_ratio를 첫 split(path=[True])에 현재 ratio로 재설정 → 응답에 root
    probe = rpc("layout.set_split_ratio", {"tab_id": TAB, "path": [True], "ratio": 0.5})
    if "error" in probe:
        # 첫 split 없으면 (우측 열 없음) 그냥 종료
        print("no right column / split (skip)", file=sys.stderr)
        return
    root = probe["result"]["layout"]["root"]

    # 2. 우측 열 down-split 수집
    splits = []
    collect_splits(root, [], splits, False)  # root에서 시작, is_right_column=False (root = right split)
    if not splits:
        print("no down-splits in right column (skip)", file=sys.stderr)
        return

    # 3. 각 split 등분 ratio로 설정
    for sp in splits:
        ratio = round(sp["ratio"], 6)
        result = rpc("layout.set_split_ratio", {
            "tab_id": TAB,
            "path": [bool(p) for p in sp["path"]],
            "ratio": ratio,
        })
        ok = "error" not in result
        print(f"path={sp['path']} ratio={sp['ratio']:.3f} ({sp['first_leaves']}/{sp['total']}) -> {'OK' if ok else 'FAIL'}")

    print("equalized")


if __name__ == "__main__":
    main()