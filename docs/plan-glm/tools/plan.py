#!/usr/bin/env python3
"""Herramientas stdlib del handoff. No ejecutan la app, Git ni red.

PLAN.json es autoridad de tickets; STATE.json, de ejecución. build escribe
únicamente tickets Markdown derivados y DOCUMENTO-MAESTRO.md en este paquete.
validate/status/baseline/selftest son de lectura; selftest modifica copias RAM.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
STATUSES = {"todo", "in_progress", "blocked", "review", "done", "deferred"}
AC_STATUSES = {"NOT_RUN", "PASS", "FAIL"}
KINDS = {"automated", "manual", "inspection"}
CHAPTERS = [
    "START-HERE.md", "ADDENDUM.md", "DECISIONS.md", "PRODUCT.md",
    "CODE-MAP.md", "ARCHITECTURE.md", "UX.md", "QA.md",
    "ROADMAP.md", "BUSINESS.md", "SESSIONS.md", "sessions/TEMPLATE.md",
]
LINK = re.compile(r"(?<!!)\[[^\]\n]+\]\(([^\s)]+)\)")


def read_json(name: str):
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


def revision_valid(value):
    return isinstance(value, str) and bool(re.fullmatch(r"[0-9a-f]{40}|working-tree:[0-9a-f]{64}", value))


def safe_relative(value):
    if not isinstance(value, str) or not value:
        return False
    p = Path(value)
    return not p.is_absolute() and ".." not in p.parts


def validate_data(plan, state, root=ROOT, check_evidence=True):
    errors = []
    if plan.get("schema_version") != 1 or state.get("schema_version") != 1:
        errors.append("schema_version debe ser 1")
    items = plan.get("tickets", [])
    ids = [t.get("id") for t in items]
    if len(ids) != len(set(ids)):
        errors.append("IDs de ticket duplicados")
    indexed = {t.get("id"): t for t in items}
    states = state.get("tickets", {})
    if set(states) != set(ids):
        errors.append("STATE y PLAN no tienen los mismos tickets")
    all_ac = set()
    for t in items:
        tid = t.get("id")
        if not isinstance(tid, str) or not re.fullmatch(r"V\d{2,}", tid):
            errors.append(f"ID inválido: {tid}")
        for key in ("title", "files", "reads", "steps", "acceptance", "tests", "stop_conditions", "contracts"):
            if not t.get(key):
                errors.append(f"{tid}: falta {key}")
        deps = t.get("depends_on", [])
        if len(deps) != len(set(deps)):
            errors.append(f"{tid}: dependencias duplicadas")
        for dep in deps:
            if dep not in indexed or dep == tid:
                errors.append(f"{tid}: dependencia inválida {dep}")
        for p in t.get("files", []) + t.get("reads", []):
            if not safe_relative(p):
                errors.append(f"{tid}: ruta no relativa/segura {p}")
        for p in t.get("contracts", []):
            if not safe_relative(p) or not (root / p).is_file():
                errors.append(f"{tid}: contrato inexistente {p}")
        for f in t.get("findings", []):
            if not re.fullmatch(r"F(?:0[1-9]|1[0-9]|20)", f):
                errors.append(f"{tid}: hallazgo desconocido {f}")
        for ac in t.get("acceptance", []):
            aid = ac.get("id", "")
            if aid in all_ac or not aid.startswith(str(tid) + "-AC"):
                errors.append(f"{tid}: AC inválido/duplicado {aid}")
            all_ac.add(aid)
            if ac.get("kind") not in KINDS or not ac.get("criterion"):
                errors.append(f"{aid}: falta tipo/criterio")
        s = states.get(tid, {})
        status = s.get("status")
        if status not in STATUSES:
            errors.append(f"{tid}: status inválido {status}")
        if status in {"in_progress", "review", "done"}:
            for key in ("owner", "session", "branch", "base_commit", "worktree"):
                if not s.get(key):
                    errors.append(f"{tid}: {status} sin {key}")
            if not re.fullmatch(r"[0-9a-f]{40}", str(s.get("base_commit", ""))):
                errors.append(f"{tid}: base_commit inválido")
            if any(states.get(dep, {}).get("status") != "done" for dep in deps):
                errors.append(f"{tid}: {status} con dependencias no terminadas")
        if status == "blocked" and not s.get("blocker"):
            errors.append(f"{tid}: blocked sin blocker")
        ac_state = s.get("acceptance", {})
        if set(ac_state) != {a["id"] for a in t.get("acceptance", [])}:
            errors.append(f"{tid}: AC en STATE distintos de PLAN")
        for aid, result in ac_state.items():
            ast = result.get("status")
            if ast not in AC_STATUSES:
                errors.append(f"{aid}: status inválido")
            if ast == "PASS":
                for key in ("evidence", "verified_at", "verified_by", "code_revision"):
                    if not result.get(key):
                        errors.append(f"{aid}: PASS sin {key}")
                if not revision_valid(result.get("code_revision")):
                    errors.append(f"{aid}: revision inválida")
                try:
                    datetime.fromisoformat(str(result.get("verified_at", "")).replace("Z", "+00:00"))
                except ValueError:
                    errors.append(f"{aid}: fecha inválida")
                for ev in result.get("evidence", []):
                    if not safe_relative(ev) or not ev.startswith("evidence/"):
                        errors.append(f"{aid}: evidencia fuera de evidence/ {ev}")
                    elif check_evidence and (not (root / ev).is_file() or (root / ev).stat().st_size == 0):
                        errors.append(f"{aid}: evidencia ausente/vacía {ev}")
        if status in {"review", "done"}:
            if not revision_valid(s.get("code_revision")):
                errors.append(f"{tid}: {status} sin revision válida")
            handoff = s.get("handoff")
            if not safe_relative(handoff) or not str(handoff).startswith("sessions/") or handoff == "sessions/TEMPLATE.md":
                errors.append(f"{tid}: {status} sin cierre válido")
            elif check_evidence and not (root / handoff).is_file():
                errors.append(f"{tid}: cierre inexistente")
        if status == "done":
            if not s.get("reviewed_by"):
                errors.append(f"{tid}: done sin revisión registrada")
            if not re.fullmatch(r"[0-9a-f]{40}", str(s.get("code_revision", ""))):
                errors.append(f"{tid}: done exige revisión de commit integrado; working-tree queda review")
            for aid, result in ac_state.items():
                if result.get("status") != "PASS":
                    errors.append(f"{tid}: done con {aid} pendiente/fallido")
                if result.get("code_revision") != s.get("code_revision"):
                    errors.append(f"{tid}: {aid} no revalidado contra revision final")
    visiting, visited = set(), set()

    def visit(tid):
        if tid in visiting:
            errors.append(f"ciclo de dependencias en {tid}")
            return
        if tid in visited or tid not in indexed:
            return
        visiting.add(tid)
        for dep in indexed[tid].get("depends_on", []):
            visit(dep)
        visiting.remove(tid)
        visited.add(tid)

    for tid in ids:
        visit(tid)
    active = [t for t in items if states.get(t["id"], {}).get("status") == "in_progress"]
    for index, left in enumerate(active):
        for right in active[index + 1:]:
            overlaps = set(left["files"]) & set(right["files"])
            if overlaps:
                errors.append(f"ownership solapado {left['id']}/{right['id']}: {sorted(overlaps)}")
    if not state.get("implementation_started") and any(s.get("status") in {"in_progress", "review", "done"} for s in states.values()):
        errors.append("Hay trabajo iniciado pero implementation_started=false")
    return errors


def code_link(path, ticket=False):
    prefix = "../../../" if ticket else "../../"
    if (REPO / path).is_file():
        return f"[{path}]({prefix}{path})"
    return f"`{path}` — propuesto, verificar antes de crear"


def render_ticket(t):
    tid = t["id"]
    lines = [f"# {tid} — {t['title']}", "", "<!-- DERIVADO de PLAN.json. Editar PLAN.json y ejecutar tools/plan.py build. Estado solo en STATE.json. -->", "",
        f"Gate: **{t['gate']}** · Esfuerzo estimado de ingeniería: **{t['estimated_engineering_days']} días** · Dependencias: **{', '.join(t['depends_on']) or 'ninguna'}**.", "",
        "## Estado y precondiciones", "", f"Consultar `{tid}` en [STATE.json](../STATE.json). No usar este ticket como registro de ejecución. Inicialmente el plan no está implementado. Leer [START-HERE](../START-HERE.md) y el último cierre antes de reclamar ownership.", "",
        "Si una dependencia está review/blocked, no cuenta como integrada. Si el código cambió desde el baseline, buscar símbolos/callers y comprobar evidencia del nuevo HEAD. La autorización de implementar este ticket cubre su alcance local; no cobro, publicación, instalación global ni envío de mensajes.", "",
        "## Problema y origen", "", f"Hallazgos cubiertos: {', '.join(t['findings']) or 'función/validación de producto, no bug baseline asignado'}. Revisar sus evidencias en [AUDITORIA-ORIGINAL](../AUDITORIA-ORIGINAL.md) y precisiones en [ADDENDUM](../ADDENDUM.md).", "",
        "## Lecturas obligatorias", ""]
    lines += [f"- [{p}](../{p})" for p in t["contracts"]]
    lines += [f"- {code_link(p, True)}" for p in t["reads"]]
    lines += ["", "## Ownership: archivos permitidos", "", "Responsabilidad de implementación y pruebas de este ticket. Si un archivo ya existe, inspeccionarlo y adaptar su contrato; no sobrescribir trabajo previo. Para ampliar la lista por un caller necesario, registrar la razón en PLAN y validar solapamientos.", ""]
    lines += [f"- {code_link(p, True)}" for p in t["files"]]
    lines += ["", "## Pasos ordenados", ""]
    lines += [f"{i}. {s}" for i, s in enumerate(t["steps"], 1)]
    lines += ["", "## Pruebas y verificaciones", "", "Los comandos siguientes son instrucciones para la futura sesión autorizada, **no resultados obtenidos al crear el handoff**. Registrar cwd, HEAD, exit code y warnings. Tests de UI/OS no se sustituyen por inspección.", ""]
    lines += [f"- {s}" for s in t["tests"]]
    lines += ["", "## Criterios de aceptación", "", "| ID | Tipo de evidencia | Condición para PASS |", "|---|---|---|"]
    lines += [f"| {a['id']} | {a['kind']} | {a['criterion']} |" for a in t["acceptance"]]
    lines += ["", "## Condiciones de pausa", ""]
    lines += [f"- {s}" for s in t["stop_conditions"]]
    lines += ["- Una prueba real puede modificar permisos, grabar, usar claves o requerir pago: comprobar autorización de la sesión y usar perfil QA. La falta de permiso deja ese AC NOT_RUN; no impide avanzar pruebas puras independientes.", "",
        "## Límites y migración", "", "No tocar módulos ajenos para limpiar estilo. No eliminar datos reales para facilitar pruebas. No elevar mínimo macOS, cambiar proveedor, nombre o promesa comercial sin decisión registrada. Conservar compatibilidad de callers hasta completar su migración; no dejar adapters paralelos sin ticket de retiro.", "",
        "## Cierre para el siguiente agente", "", f"Crear `sessions/FECHA-{tid}-OWNER.md` desde [TEMPLATE](../sessions/TEMPLATE.md), sustituyendo FECHA/OWNER por identidad real. Registrar archivos/símbolos tocados, AC por ID, comandos/resultados, revision, decisiones, evidencia y próximo paso exacto. Actualizar STATE como in_progress/blocked/review; done solo tras revisión y evidencia de todos los AC en el commit integrado. Actualizar derivados con `python3 -B docs/plan-glm/tools/plan.py build` y ejecutar `python3 -B docs/plan-glm/tools/plan.py validate`. No hacer commit/push sin autorización vigente.", ""]
    return "\n".join(lines)


def relocate_links(text, source):
    def replace(match):
        target = match.group(1)
        if target.startswith(("https://", "http://", "app://", "#", "/")):
            return match.group(0)
        suffix = ""
        path_part = target
        if "#" in target:
            path_part, fragment = target.split("#", 1)
            suffix = "#" + fragment
        resolved = (source.parent / path_part).resolve()
        import os
        return match.group(0).replace(target, Path(os.path.relpath(resolved, ROOT)).as_posix() + suffix)
    return LINK.sub(replace, text)


def master_text(plan):
    chunks = ["# VOZA — documento maestro para GLM 5.3 Flash", "",
        "**Paquete documental 1.0 · 2026-09-07 · implementación no iniciada en la entrega inicial.**", "",
        "Este archivo reúne los contratos, el mapa, los tickets completos y la auditoría original íntegra. Es DERIVADO: editar los documentos fuente o PLAN.json y ejecutar `python3 -B docs/plan-glm/tools/plan.py build`. El estado vigente de ejecución se consulta en STATE.json; este documento no certifica tareas hechas. Para una sesión de trabajo empezar por START-HERE.md, no consumir todo este archivo como contexto obligatorio.", "",
        "## Índice de fuentes", ""]
    chunks += [f"- [{name}]({name})" for name in CHAPTERS]
    chunks += ["- [PLAN.json](PLAN.json): autoridad de tickets, DAG y criterios.", "- [STATE.json](STATE.json): estado mutable, owner y evidencia.", "- [Corpus semilla](fixtures/polished-seed.json): sintético, sin evaluación humana.", "- [Fuentes web](SOURCES.md): enlaces/fecha de consulta de la auditoría.", "- [Auditoría íntegra](AUDITORIA-ORIGINAL.md): informe histórico completo."]
    for name in CHAPTERS:
        p = ROOT / name
        chunks += ["", "---", "", f"# Documento fuente: {name}", "", relocate_links(p.read_text(encoding="utf-8"), p)]
    for t in plan["tickets"]:
        p = ROOT / "tickets" / f"{t['id']}.md"
        chunks += ["", "---", "", relocate_links(render_ticket(t), p)]
    for name in ["SOURCES.md", "AUDITORIA-ORIGINAL.md"]:
        p = ROOT / name
        chunks += ["", "---", "", f"# Documento fuente: {name}", "", relocate_links(p.read_text(encoding="utf-8"), p)]
    return "\n".join(chunks).rstrip() + "\n"


def check_links():
    errors = []
    checked = 0
    for p in ROOT.rglob("*.md"):
        for match in LINK.finditer(p.read_text(encoding="utf-8")):
            target = match.group(1)
            if target.startswith(("https://", "http://", "app://", "#", "mailto:")):
                continue
            target = re.sub(r":\d+$", "", target.split("#", 1)[0])
            resolved = Path(target) if target.startswith("/") else p.parent / target
            checked += 1
            if not resolved.exists():
                errors.append(f"link roto {p.relative_to(ROOT)}: {target}")
    return checked, errors


def baseline_result():
    baseline = read_json("evidence/baseline.json")
    changed = []
    for path, expected in baseline["code_files"].items():
        p = REPO / path
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != expected["sha256"]:
            changed.append(path)
    return {"baseline_commit": baseline["commit"], "checked": len(baseline["code_files"]), "original_files_unchanged": not changed, "changed": changed}


def selftest(plan, state):
    results = []
    tests = [
        ("ciclo", lambda p, s: p["tickets"][0]["depends_on"].append("V02")),
        ("dependencia_inexistente", lambda p, s: p["tickets"][0]["depends_on"].append("V999")),
        ("id_duplicado", lambda p, s: p["tickets"].append(copy.deepcopy(p["tickets"][0]))),
        ("done_sin_evidencia", lambda p, s: s["tickets"]["V01"].update(status="done")),
        ("pass_sin_evidencia", lambda p, s: s["tickets"]["V01"]["acceptance"]["V01-AC01"].update(status="PASS")),
        ("bloqueo_sin_razon", lambda p, s: s["tickets"]["V01"].update(status="blocked")),
        ("ruta_fuera_repo", lambda p, s: p["tickets"][0]["files"].append("../../private")),
        ("ac_perdido", lambda p, s: s["tickets"]["V01"]["acceptance"].pop("V01-AC01")),
    ]
    for name, mutate in tests:
        p, s = copy.deepcopy(plan), copy.deepcopy(state)
        mutate(p, s)
        rejected = bool(validate_data(p, s, check_evidence=False))
        results.append({"case": name, "expectation_met": rejected})
    p, s = copy.deepcopy(plan), copy.deepcopy(state)
    s["implementation_started"] = True
    record = s["tickets"]["V01"]
    record.update(status="done", owner="synthetic-test", session="synthetic-test",
                  branch="synthetic-test", base_commit="a" * 40,
                  worktree="/synthetic-not-a-real-checkout", code_revision="b" * 40,
                  reviewed_by="synthetic-test", handoff="sessions/synthetic-test.md")
    for ac in record["acceptance"].values():
        ac.update(status="PASS", evidence=["evidence/synthetic-test.json"],
                  verified_at="2026-09-07T00:00:00Z", verified_by="synthetic-test",
                  code_revision="b" * 40)
    results.append({"case": "valid_state_fixture_in_memory", "expectation_met": not validate_data(p, s, check_evidence=False)})
    p, s = copy.deepcopy(plan), copy.deepcopy(state)
    s["implementation_started"] = True
    p["tickets"][1]["depends_on"] = []
    p["tickets"][1]["files"].append(p["tickets"][0]["files"][0])
    for tid in ["V01", "V02"]:
        s["tickets"][tid].update(status="in_progress", owner=tid, session=tid,
            branch="synthetic-test", base_commit="a" * 40, worktree="/synthetic")
    overlap_errors = validate_data(p, s, check_evidence=False)
    results.append({"case": "overlapping_owners_rejected", "expectation_met": any("ownership solapado" in e for e in overlap_errors)})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "validate", "status", "baseline", "selftest"])
    args = parser.parse_args()
    if args.command == "baseline":
        result = baseline_result()
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["original_files_unchanged"] else 1
    plan, state = read_json("PLAN.json"), read_json("STATE.json")
    errors = validate_data(plan, state)
    if errors:
        print(json.dumps({"ok": False, "errors": errors}, ensure_ascii=False, indent=2))
        return 1
    if args.command == "selftest":
        results = selftest(plan, state)
        print(json.dumps(results, ensure_ascii=False, indent=2))
        return 0 if all(r["expectation_met"] for r in results) else 1
    if args.command == "status":
        rows = []
        for t in plan["tickets"]:
            s = state["tickets"][t["id"]]
            missing = [d for d in t["depends_on"] if state["tickets"][d]["status"] != "done"]
            rows.append({"ticket": t["id"], "title": t["title"], "status": s["status"], "available": s["status"] == "todo" and not missing, "waiting_for": missing, "owner": s["owner"]})
        print(json.dumps({"product_gates": state["product_gates"], "tickets": rows}, ensure_ascii=False, indent=2))
        return 0
    if args.command == "build":
        for t in plan["tickets"]:
            (ROOT / "tickets" / f"{t['id']}.md").write_text(render_ticket(t), encoding="utf-8")
        (ROOT / "DOCUMENTO-MAESTRO.md").write_text(master_text(plan), encoding="utf-8")
        print(json.dumps({"built_tickets": len(plan["tickets"]), "master": str(ROOT / "DOCUMENTO-MAESTRO.md")}, ensure_ascii=False))
        return 0
    for t in plan["tickets"]:
        p = ROOT / "tickets" / f"{t['id']}.md"
        if not p.is_file() or p.read_text(encoding="utf-8") != render_ticket(t):
            errors.append(f"{t['id']}: Markdown derivado ausente/desactualizado; ejecutar build")
    p = ROOT / "DOCUMENTO-MAESTRO.md"
    if not p.is_file() or p.read_text(encoding="utf-8") != master_text(plan):
        errors.append("DOCUMENTO-MAESTRO.md ausente/desactualizado; ejecutar build")
    covered = {f for t in plan["tickets"] for f in t["findings"]}
    if covered != {f"F{i:02}" for i in range(1, 21)}:
        errors.append("No todos los F01–F20 están cubiertos")
    audit = (ROOT / "AUDITORIA-ORIGINAL.md").read_text(encoding="utf-8")
    original = audit.split("\n\n", 1)[1]
    if original.endswith("\n"):
        original = original[:-1]
    baseline = read_json("evidence/baseline.json")
    if len(original) != baseline["audit_chars"] or hashlib.sha256(original.encode()).hexdigest() != baseline["audit_sha256"]:
        errors.append("Auditoría original alterada respecto al registro de procedencia")
    seed = read_json("fixtures/polished-seed.json")
    cases = seed.get("cases", [])
    if seed.get("status") != "SYNTHETIC_NOT_HUMAN_VALIDATED" or not seed.get("not_a_benchmark"):
        errors.append("Corpus semilla indebidamente etiquetado como evidencia")
    if len({c.get("id") for c in cases}) != len(cases):
        errors.append("IDs duplicados en corpus semilla")
    for c in cases:
        if c.get("human_reviewed") is not False or c.get("split") != "seed_not_holdout":
            errors.append(f"Semilla {c.get('id')} no mantiene separación de benchmark")
    for t in plan["tickets"]:
        for path in t["files"]:
            if path not in (ROOT / "CODE-MAP.md").read_text(encoding="utf-8"):
                errors.append(f"CODE-MAP no contiene {path}")
    checked, link_errors = check_links()
    errors += link_errors
    print(json.dumps({"ok": not errors, "tickets": len(plan["tickets"]), "acceptance_criteria": sum(len(t["acceptance"]) for t in plan["tickets"]), "local_links_checked": checked, "errors": errors, "scope": "documentation_structure_only_not_product_verification"}, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
