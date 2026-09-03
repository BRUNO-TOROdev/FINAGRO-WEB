"""Extract the official FINAGRO V1 chart template from the blank workbook.

The workbook is read-only. Generated JSON, audit Markdown and migration are
deterministic and intentionally contain no data from operational companies.
"""

from __future__ import annotations

import hashlib
import json
import posixpath
import re
import sys
import uuid
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
NS = {"m": MAIN, "r": REL, "p": PKG}
ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "source-local" / "FINAGRO - Planilha Financeira (Em branco).xlsx"
CANONICAL_PATH = ROOT / "docs" / "data" / "finagro-chart-template-v1.json"
AUDIT_PATH = ROOT / "docs" / "data" / "FINAGRO_CHART_TEMPLATE_AUDIT.md"
MIGRATION_PATH = ROOT / "supabase" / "migrations" / "202609030008_official_finagro_chart_template.sql"
TEMPLATE_ID = uuid.uuid5(uuid.NAMESPACE_URL, "finagro-web/chart-template/official/v1")
ITEM_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "finagro-web/chart-template/official/v1/items")

AUXILIARY_HEADERS = {"STATUS", "Pgto", "Funcionários", "SAFRA/SAFRINHA", "Bancos"}
HEADER_ALIASES = {
    "Desp_com_Pessoal_Agricultura": "Despesa_com_Pessoal_Agricultura",
    "Desp_com_Pessoal_Pecuária": "Despesa_com_Pessoal_Pecuária",
}
AUTHORIZED_COLLISIONS = {
    frozenset(("Entrada_de_Financiamento", "Entrada de Financiamento")),
    frozenset(("Saldo_Inicial_de_Caixa", "Saldo Inicial de Caixa")),
}


def column_number(name: str) -> int:
    result = 0
    for char in name:
        result = result * 26 + ord(char) - 64
    return result


def parse_ref(reference: str) -> tuple[str, int, str, int]:
    match = re.fullmatch(r"([A-Z]+)(\d+):([A-Z]+)(\d+)", reference)
    if not match:
        raise ValueError(f"Unsupported Excel reference: {reference}")
    return match.group(1), int(match.group(2)), match.group(3), int(match.group(4))


def shared_text(node: ET.Element) -> str:
    return "".join(part.text or "" for part in node.iter(f"{{{MAIN}}}t"))


def load_workbook(source: Path) -> tuple[dict[str, str], list[dict[str, object]], list[dict[str, object]]]:
    with zipfile.ZipFile(source) as archive:
        shared: list[str] = []
        if "xl/sharedStrings.xml" in archive.namelist():
            root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            shared = [shared_text(item) for item in root.findall("m:si", NS)]

        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        workbook_rels = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        targets = {item.attrib["Id"]: item.attrib["Target"] for item in workbook_rels.findall("p:Relationship", NS)}
        sheet_node = next(item for item in workbook.findall("m:sheets/m:sheet", NS) if item.attrib["name"] == "Plano de Contas")
        target = targets[sheet_node.attrib[f"{{{REL}}}id"]].lstrip("/")
        sheet_path = target if target.startswith("xl/") else f"xl/{target}"
        sheet = ET.fromstring(archive.read(sheet_path))

        cells: dict[str, str] = {}
        for cell in sheet.iter(f"{{{MAIN}}}c"):
            value_node = cell.find("m:v", NS)
            if value_node is None:
                continue
            raw = value_node.text or ""
            cells[cell.attrib["r"]] = shared[int(raw)] if cell.attrib.get("t") == "s" and raw.isdigit() else raw

        rel_path = posixpath.join(posixpath.dirname(sheet_path), "_rels", posixpath.basename(sheet_path) + ".rels")
        rels = ET.fromstring(archive.read(rel_path))
        sheet_targets = {item.attrib["Id"]: item.attrib["Target"] for item in rels.findall("p:Relationship", NS)}
        tables: list[dict[str, object]] = []
        for part in sheet.findall("m:tableParts/m:tablePart", NS):
            target = sheet_targets[part.attrib[f"{{{REL}}}id"]]
            table_path = posixpath.normpath(posixpath.join(posixpath.dirname(sheet_path), target))
            table = ET.fromstring(archive.read(table_path))
            start_col, start_row, end_col, end_row = parse_ref(table.attrib["ref"])
            if start_col != end_col:
                raise ValueError(f"Expected one-column list, found {table.attrib['ref']}")
            values = [cells[f"{start_col}{row}"] for row in range(start_row, end_row + 1) if f"{start_col}{row}" in cells]
            tables.append({"range": table.attrib["ref"], "column": start_col, "start_row": start_row, "values": values})

        # Evidence from the operational Group/Subgroup validation.
        validation_evidence: list[dict[str, object]] = []
        workbook_sheet = next(item for item in workbook.findall("m:sheets/m:sheet", NS) if item.attrib["name"] == "Base de Dados")
        target = targets[workbook_sheet.attrib[f"{{{REL}}}id"]].lstrip("/")
        base_path = target if target.startswith("xl/") else f"xl/{target}"
        base = ET.fromstring(archive.read(base_path))
        for validation in base.iter():
            if not validation.tag.endswith("dataValidation"):
                continue
            sqref = validation.attrib.get("sqref")
            if sqref is None:
                node = next((child for child in validation if child.tag.endswith("sqref")), None)
                sqref = "".join(node.itertext()) if node is not None else None
            formulas = ["".join(child.itertext()) for child in validation if child.tag.endswith(("formula1", "formula2"))]
            validation_evidence.append({"cell": sqref, "type": validation.attrib.get("type"), "formulas": formulas})
        return cells, tables, validation_evidence


def build_canonical(source: Path) -> dict[str, object]:
    cells, tables, validations = load_workbook(source)
    master = next(table for table in tables if table["range"] == "B6:B33")
    groups = list(master["values"])[1:]
    account_tables = [table for table in tables if table["values"] and table["values"][0] not in AUXILIARY_HEADERS and table is not master]
    auxiliary = [table for table in tables if table["values"] and table["values"][0] in AUXILIARY_HEADERS]
    items: list[dict[str, object]] = []

    for group_order, source_name in enumerate(groups, 1):
        group_code = f"FINAGRO-V1-G{group_order:03d}"
        origin_row = 6 + group_order
        header = HEADER_ALIASES.get(source_name, source_name)
        matches = [table for table in account_tables if table["values"][0] == header]
        if len(matches) > 1:
            raise ValueError(f"Multiple subgroup lists found for {source_name}")
        aliases = [header] if header != source_name else []
        group_id = uuid.uuid5(ITEM_NAMESPACE, group_code)
        items.append({
            "id": str(group_id), "code": group_code, "code_type": "INTERNAL_TECHNICAL",
            "source_name": source_name, "display_name": source_name.replace("_", " "),
            "source_type": "GRUPO", "source_origin": f"Plano de Contas!B{origin_row}",
            "source_aliases": aliases, "level": 1, "parent_id": None, "parent_code": None,
            "display_order": group_order, "managerial_type": "OUTRO", "nature": "NEUTRA",
            "participates_dre": False, "participates_cashflow": False,
            "requires_farm": False, "allows_allocation": False, "requires_crop_season": False,
        })
        if not matches:
            continue
        table = matches[0]
        for child_order, child_name in enumerate(table["values"][1:], 1):
            child_code = f"{group_code}-S{child_order:03d}"
            items.append({
                "id": str(uuid.uuid5(ITEM_NAMESPACE, child_code)), "code": child_code,
                "code_type": "INTERNAL_TECHNICAL", "source_name": child_name,
                "display_name": child_name.replace("_", " "), "source_type": "SUBGRUPO",
                "source_origin": f"Plano de Contas!{table['column']}{int(table['start_row']) + child_order}",
                "source_aliases": [], "level": 2, "parent_id": str(group_id), "parent_code": group_code,
                "display_order": child_order, "managerial_type": "OUTRO", "nature": "NEUTRA",
                "participates_dre": False, "participates_cashflow": False,
                "requires_farm": False, "allows_allocation": False, "requires_crop_season": False,
            })

    collisions: dict[str, set[str]] = {}
    for item in items:
        collisions.setdefault(str(item["display_name"]), set()).add(str(item["source_name"]))
    unexpected = [values for values in collisions.values() if len(values) > 1 and frozenset(values) not in AUTHORIZED_COLLISIONS]
    if unexpected:
        raise ValueError(f"Unapproved underscore collisions: {unexpected}")
    if len(groups) != 27 or sum(item["source_type"] == "SUBGRUPO" for item in items) != 127:
        raise ValueError("Official source reconciliation changed: expected 27 groups and 127 subgroups")

    return {
        "schema_version": 1,
        "template": {"id": str(TEMPLATE_ID), "name": "FINAGRO", "version": "1.0.0"},
        "source": {"file": source.name, "sheet": "Plano de Contas", "sha256": hashlib.sha256(source.read_bytes()).hexdigest()},
        "extraction": {
            "group_list": "Plano de Contas!B6:B33", "group_validation": "Base de Dados!D7 = Tb_Plano_de_Contas",
            "subgroup_validation": "Base de Dados!E7 = INDIRECT($D7)", "display_transform": "underscore_to_space_only",
            "code_strategy": "stable_internal_technical_not_accounting", "neutral_schema_defaults": True,
        },
        "counts": {"groups": 27, "subgroups": 127, "total": 154},
        "auxiliary_lists": [{"source_name": table["values"][0], "range": table["range"], "values": table["values"][1:]} for table in auxiliary],
        "validation_evidence": validations,
        "items": items,
    }


def audit_markdown(data: dict[str, object]) -> str:
    items = data["items"]
    groups = [item for item in items if item["source_type"] == "GRUPO"]
    children = {group["id"]: [item for item in items if item["parent_id"] == group["id"]] for group in groups}
    lines = [
        "# Auditoria do Template Oficial do Plano de Contas FINAGRO V1", "",
        "## Fonte e reconciliação", "",
        f"- Arquivo: `{data['source']['file']}` (não versionado).",
        "- Aba exclusiva: `Plano de Contas`.",
        f"- SHA-256 da fonte: `{data['source']['sha256']}`.",
        "- Lista operacional de Grupos: `Plano de Contas!B6:B33` (`Plano_de_Contas`).",
        "- Validação operacional: `Base de Dados!D7 = Tb_Plano_de_Contas`.",
        "- Validação de Subgrupo: `Base de Dados!E7 = INDIRECT($D7)`.",
        f"- Grupos: **{data['counts']['groups']}**.", f"- Subgrupos: **{data['counts']['subgroups']}**.",
        f"- Total: **{data['counts']['total']}**.", "",
        "## Relação completa Grupo → Subgrupos", "",
    ]
    for group in groups:
        lines.append(f"### {group['display_order']}. `{group['source_name']}` → {json.dumps(group['display_name'], ensure_ascii=False)}")
        lines.append("")
        if children[group["id"]]:
            lines.extend(f"- `{child['source_name']}` → {json.dumps(child['display_name'], ensure_ascii=False)}" for child in children[group["id"]])
        else:
            lines.append("- *(nenhum Subgrupo presente na fonte)*")
        lines.append("")
    lines += ["## Listas auxiliares ignoradas", ""]
    for table in data["auxiliary_lists"]:
        lines.append(f"- `{table['source_name']}` — `{table['range']}` — não pertence ao Plano de Contas.")
    lines += [
        "", "## Colisões autorizadas e intencionais", "",
        "- Nível 1 `Entrada_de_Financiamento` → `Entrada de Financiamento`; nível 2 `Entrada de Financiamento` → `Entrada de Financiamento`.",
        "- Nível 1 `Saldo_Inicial_de_Caixa` → `Saldo Inicial de Caixa`; nível 2 `Saldo Inicial de Caixa` → `Saldo Inicial de Caixa`.",
        "- Os registros permanecem distintos por `id`, `level` e `parent_id`; nenhum qualificador artificial foi adicionado.", "",
        "## Divergências e aliases", "",
        "- O Grupo operacional é `Desp_com_Pessoal_Agricultura`; `Despesa_com_Pessoal_Agricultura` é somente o cabeçalho da lista auxiliar de Subgrupos em `N6`.",
        "- O Grupo operacional é `Desp_com_Pessoal_Pecuária`; `Despesa_com_Pessoal_Pecuária` é somente o cabeçalho da lista auxiliar de Subgrupos em `R6`.",
        "- Evidência: `Tb_Plano_de_Contas` alimenta Grupo; `INDIRECT($D7)` resolve as tabelas `Desp_com_Pessoal_*`; DRE, DRE Safra, Fluxo de Caixa, Projeção e Projetado × Realizado usam `Desp_com_Pessoal_*`.",
        "- Não foram criados Grupos duplicados para os cabeçalhos variantes.", "",
        "## Nomes incomuns e inconsistências preservadas", "",
        "- Espaços finais presentes na fonte foram preservados em `Encargos sociais `, `Consultoria ` e `Fretes e carretos `.",
        "- Grafias como `Produtos Quimicos`, `Armazem/Secador`, `licensas`, `gtas`, `Pro-labore` e `Outros*` foram preservadas sem correção.",
        "- `Entradas_Não_Operacionais` existe na lista de Grupos, mas não possui lista de Subgrupos válida na aba.", "",
        "## Decisões técnicas", "",
        "- `display_name` substitui exclusivamente `_` por espaço; nenhum outro caractere é normalizado.",
        "- Códigos `FINAGRO-V1-*` são identificadores internos estáveis, não códigos contábeis oficiais.",
        "- A fonte não fornece os campos gerenciais exigidos pelo novo schema. O template usa `OUTRO`/`NEUTRA` e flags financeiras desativadas, sem inferência silenciosa.",
        "- `source_name`, `display_name`, nível, pai, tipo de origem, célula de origem e aliases ficam auditáveis no JSON e no banco.", "",
    ]
    return "\n".join(lines)


def migration_sql(data: dict[str, object]) -> str:
    payload = json.dumps(data["items"], ensure_ascii=False, separators=(",", ":"))
    template = data["template"]
    return f"""-- FINAGRO Web — Official FINAGRO chart template V1
-- Generated from the blank workbook, sheet \"Plano de Contas\".

alter table public.chart_account_template_items
    add column source_name text,
    add column source_type text check (source_type in ('GRUPO','SUBGRUPO')),
    add column source_origin text,
    add column source_aliases jsonb not null default '[]'::jsonb
        check (jsonb_typeof(source_aliases) = 'array');

alter table public.chart_accounts
    add column source_name text,
    add column source_type text check (source_type in ('GRUPO','SUBGRUPO')),
    add column source_origin text;

insert into public.chart_account_templates (id, name, version, is_active)
values ('{template['id']}', '{template['name']}', '{template['version']}', true)
on conflict (id) do update set name=excluded.name, version=excluded.version, is_active=true;

with source as (
    select value as item
      from jsonb_array_elements($finagro${payload}$finagro$::jsonb)
)
insert into public.chart_account_template_items (
    id, template_id, parent_item_id, code, name, managerial_type, nature,
    participates_dre, participates_cashflow, requires_farm, allows_allocation,
    requires_crop_season, display_order, source_name, source_type, source_origin,
    source_aliases
)
select
    (item->>'id')::uuid, '{template['id']}', nullif(item->>'parent_id','')::uuid,
    item->>'code', item->>'display_name', item->>'managerial_type', item->>'nature',
    (item->>'participates_dre')::boolean, (item->>'participates_cashflow')::boolean,
    (item->>'requires_farm')::boolean, (item->>'allows_allocation')::boolean,
    (item->>'requires_crop_season')::boolean, (item->>'display_order')::integer,
    item->>'source_name', item->>'source_type', item->>'source_origin', item->'source_aliases'
from source
on conflict (id) do update set
    parent_item_id=excluded.parent_item_id, code=excluded.code, name=excluded.name,
    managerial_type=excluded.managerial_type, nature=excluded.nature,
    participates_dre=excluded.participates_dre, participates_cashflow=excluded.participates_cashflow,
    requires_farm=excluded.requires_farm, allows_allocation=excluded.allows_allocation,
    requires_crop_season=excluded.requires_crop_season, display_order=excluded.display_order,
    source_name=excluded.source_name, source_type=excluded.source_type,
    source_origin=excluded.source_origin, source_aliases=excluded.source_aliases;

create or replace function public.apply_chart_account_template(p_organization_id uuid, p_template_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
    template_row public.chart_account_templates%rowtype;
    application_id uuid;
    item record;
    id_map jsonb := '{{}}'::jsonb;
    new_account_id uuid;
    new_parent_id uuid;
begin
    if auth.uid() is null or not private.has_permission(p_organization_id, 'chart_accounts.manage') then
        raise exception 'PERMISSION_DENIED';
    end if;
    select * into template_row from public.chart_account_templates where id=p_template_id and is_active=true;
    if not found then raise exception 'CHART_ACCOUNT_TEMPLATE_NOT_FOUND'; end if;
    if not exists (select 1 from public.chart_account_template_items where template_id=p_template_id) then
        raise exception 'CHART_ACCOUNT_TEMPLATE_HAS_NO_ITEMS';
    end if;
    insert into public.organization_chart_template_applications (organization_id,template_id,template_version,applied_by)
    values (p_organization_id,p_template_id,template_row.version,auth.uid())
    on conflict (organization_id,template_id) do nothing returning id into application_id;
    if application_id is null then return false; end if;
    for item in
        with recursive template_tree as (
            select i.*,1 as depth from public.chart_account_template_items i where i.template_id=p_template_id and i.parent_item_id is null
            union all
            select i.*,t.depth+1 from public.chart_account_template_items i join template_tree t on i.parent_item_id=t.id where i.template_id=p_template_id
        ) select * from template_tree order by depth,display_order,code
    loop
        new_account_id := gen_random_uuid();
        new_parent_id := case when item.parent_item_id is null then null else (id_map->>item.parent_item_id::text)::uuid end;
        insert into public.chart_accounts (
            id,organization_id,parent_id,code,name,managerial_type,nature,
            participates_dre,participates_cashflow,requires_farm,allows_allocation,
            requires_crop_season,display_order,source_template_id,source_template_item_id,
            source_template_version,source_name,source_type,source_origin
        ) values (
            new_account_id,p_organization_id,new_parent_id,item.code,item.name,item.managerial_type,item.nature,
            item.participates_dre,item.participates_cashflow,item.requires_farm,item.allows_allocation,
            item.requires_crop_season,item.display_order,p_template_id,item.id,template_row.version,
            item.source_name,item.source_type,item.source_origin
        );
        id_map := id_map || jsonb_build_object(item.id::text,new_account_id::text);
    end loop;
    return true;
end;
$$;

revoke all on function public.apply_chart_account_template(uuid,uuid) from public;
grant execute on function public.apply_chart_account_template(uuid,uuid) to authenticated;
"""


def main() -> int:
    source = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else DEFAULT_SOURCE
    data = build_canonical(source)
    CANONICAL_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    AUDIT_PATH.write_text(audit_markdown(data), encoding="utf-8")
    MIGRATION_PATH.write_text(migration_sql(data), encoding="utf-8")
    print(json.dumps(data["counts"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
