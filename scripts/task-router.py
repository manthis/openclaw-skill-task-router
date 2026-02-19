#!/usr/bin/env python3
"""task-router.py — Two-axis task routing: Time × Complexity → Decision
Drop-in replacement for task-router.sh with identical output."""

import argparse
import json
import os
import re
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--task', required=True)
    parser.add_argument('--json', action='store_true', dest='json_output')
    parser.add_argument('--check-protection', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--use-notify', action='store_true')
    parser.add_argument('--no-notify', action='store_true')
    args = parser.parse_args()

    use_notify = args.use_notify and not args.no_notify
    task = args.task
    task_lower = task.lower()
    word_count = len(task.split())

    # Category scores
    scores = {k: 0 for k in ['conversation','lookup','search','content','filemod','code','debug','architecture','deploy','config']}

    def match(pattern):
        return re.search(pattern, task_lower) is not None

    # Conversation
    if re.match(r'^(ok|oui|non|yes|no|merci|thanks|super|cool|bien|parfait|good|great|salut|hello|hi|bonjour|bonsoir|hey|yo|ciao|d.accord|okay|vas-y|go|fais-le|lance|c.est bon|top|nice|lol|mdr|haha|👍|❤️|🙏)$', task_lower):
        scores['conversation'] = 10
    if re.match(r'^\s*(quel |quelle |comment |pourquoi |combien |où |quand |est-ce que |what |how |why |when |where |which |who |is |are |can |do |does )', task_lower):
        scores['conversation'] += 5
    if task_lower.rstrip().endswith('?'):
        scores['conversation'] += 3
    if match(r'\b(penses|think|opinion|avis|recommend|conseille|préfère|prefer|choix|choice)\b'):
        scores['conversation'] += 4

    # Lookup
    if match(r'\b(check|vérifie|show|affiche|list|liste|status|état|info|get|récupère|dis-moi|tell me|regarde|look|montre)\b'):
        scores['lookup'] += 5
    if match(r'\b(calendar|calendrier|agenda|weather|météo|meteo|heure|time|date|aujourd.hui|today|demain|tomorrow|rappelle|remind)\b'):
        scores['lookup'] += 6
    if match(r'\b(read|lis|log|logs|git status|git log|git diff)\b'):
        scores['lookup'] += 4

    # Search
    if match(r'\b(recherche|cherche|search|find|trouve|trouver|articles?|papers?|sources?|références?)\b'):
        scores['search'] += 5
    if match(r'\b(investigate|explore|analyze|analyse|compare|audit|review|evaluate|évalue|benchmark|état de l.art|state of the art)\b'):
        scores['search'] += 5
    if match(r'\b[0-9]+\s*(articles?|exemples?|sources?|liens?|links?|results?|résultats?|options?|alternatives?)\b'):
        scores['search'] += 4

    # Content
    if match(r'\b(rédige|draft|compose|write|écris|résume|summarize|summary|résumé|traduis|translate)\b'):
        scores['content'] += 5
    if match(r'\b(email|mail|message|lettre|letter|article|blog|post|doc|documentation|readme|rapport|report)\b'):
        scores['content'] += 4

    # Filemod
    if match(r'\b(update|met à jour|modifie|modify|change|edit|édite|améliore|improve|réécris|rewrite|ajoute|add|supprime|remove|delete|rename|renomme)\b'):
        scores['filemod'] += 5
    if match(r'\b(fichier|file|config|\.json|\.yaml|\.yml|\.toml|\.env|\.md|\.txt)\b'):
        scores['filemod'] += 3

    # Code
    if match(r'\b(code|script|function|fonction|implement|implémente|développe|develop|programme|program|endpoint|api|route|handler|middleware|class|module|package|library|lib)\b'):
        scores['code'] += 6
    if match(r'\b(crée|créer|create|build|write a|écris un)\b'):
        if scores['code'] > 0:
            scores['code'] += 4
        else:
            scores['content'] += 2
            scores['code'] += 2
    if match(r'\b(skill|plugin|tool|bot|cli|daemon|service|worker|cron|webhook|docker|container|k8s|kubernetes)\b'):
        scores['code'] += 5
    if match(r'\b(test|tests|spec|unittest|jest|pytest|ci|cd|pipeline|lint|eslint|prettier|type.?check)\b'):
        scores['code'] += 4
    if match(r'\b(refactor|refactorise|optimize|optimise|clean.?up|restructure)\b'):
        scores['code'] += 5
        scores['filemod'] += 3

    # Debug — split imperative (action) vs informational
    if match(r'\b(fix|corrige|résous|resolve|troubleshoot|répare)\b'):
        scores['debug'] += 8  # Strong: clearly requesting action
    if match(r'\b(debug|debugge|diagnose|diagnostique)\b'):
        scores['debug'] += 6  # Medium: could be question or action
    if match(r"\b(error|erreur|bug|issue|broken|cassé|crash|fail|failed|marche pas|doesn.t work|not working|problem|problème|weird|bizarre|strange|étrange)\b"):
        scores['debug'] += 5
    if match(r'\b(stack.?trace|traceback|exception|segfault|undefined|null|nan|timeout|502|500|404|403|401)\b'):
        scores['debug'] += 4

    # Architecture
    if match(r'\b(architect|architecture|design|conception|plan|planifie|stratégie|strategy|roadmap|spec|specification)\b'):
        scores['architecture'] += 7
    if match(r'\b(système|system|infrastructure|infra|stack|database|db|schema|migration|migrate|scale|scaling)\b'):
        scores['architecture'] += 4
    if match(r'\b(multi|plusieurs composants|several components|microservice|monorepo|event.?driven|pub.?sub|queue|message broker)\b'):
        scores['architecture'] += 5

    # Deploy
    if match(r'\b(deploy|déploie|publish|publie|release|ship|merge|pr |pull request|push to|vercel|netlify|heroku|aws|gcp|azure)\b'):
        scores['deploy'] += 6

    # Config
    if match(r'\b(install|installe|configure|setup|set up|config|provision|bootstrap|init|initialize)\b'):
        scores['config'] += 5
    if match(r'\b(ssh|ssl|tls|cert|certificate|dns|domain|nginx|apache|proxy|firewall|port|env|environment)\b'):
        scores['config'] += 4

    # Pre-compute question detection
    is_question = bool(task_lower.rstrip().endswith('?'))
    if re.match(r'^\s*(c.est quoi|qu.est-ce que|what is|what.s|why does|pourquoi|how |comment |explique|explain|describe|décris)', task_lower):
        is_question = True

    # Dominant category
    dominant = max(scores, key=scores.get)
    max_score = scores[dominant]
    if max_score <= 2:
        dominant = 'conversation'

    # Tie-breaking: short questions with technical keywords → prefer conversation
    if dominant != 'conversation' and is_question and word_count <= 6:
        score_diff = max_score - scores['conversation']
        if score_diff <= 3:
            dominant = 'conversation'
            max_score = scores['conversation']

    # Map category → base time + complexity
    cat_map = {
        'conversation': (10, 1, 'simple'),
        'lookup':       (12, 1, 'simple'),
        'search':       (45, 2, 'normal'),
        'content':      (50, 2, 'normal'),
        'filemod':      (40, 2, 'normal'),
        'code':         (80, 3, 'complex'),
        'debug':        (90, 3, 'complex'),
        'architecture': (120, 3, 'complex'),
        'deploy':       (60, 2, 'normal'),
        'config':       (50, 2, 'normal'),
    }
    base_time, complexity, complexity_name = cat_map[dominant]

    # Question dampener: short questions about technical topics are explanations, not work
    if is_question and word_count <= 8 and dominant in ('debug', 'code', 'architecture'):
        if word_count <= 5:
            complexity, complexity_name, base_time = 1, 'simple', 15
        else:
            complexity, complexity_name, base_time = 2, 'normal', 25

    # Medium-length explanation questions: cap at normal
    if is_question and word_count <= 12:
        if re.match(r'^\s*(c.est quoi|qu.est-ce que|what is|what.s|explain|explique|how does|comment|describe|décris)', task_lower):
            if complexity >= 3:
                complexity, complexity_name = 2, 'normal'
                base_time = min(base_time, 40)

    estimated = base_time

    # Scope adjustments
    if match(r'\b(and then|et ensuite|puis|après ça|ensuite|step.?by.?step|étape par étape)\b'):
        estimated += 30
    if match(r'\b(multiple|plusieurs|every|chaque|all|tous|toutes|each|batch|bulk)\b'):
        estimated += 20
    comma_count = task.count(',')
    if comma_count >= 2:
        estimated += comma_count * 10
    if word_count > 30:
        estimated += 40
        if complexity >= 2:
            complexity, complexity_name = 3, 'complex'
    elif word_count > 15:
        estimated += 20
    elif word_count <= 4 and dominant == 'conversation':
        estimated = min(estimated, 10)

    if scores['code'] >= 3 and scores['debug'] >= 3:
        estimated += 30
        complexity, complexity_name = 3, 'complex'
    if scores['architecture'] >= 3 and scores['code'] >= 3:
        estimated += 40
        complexity, complexity_name = 3, 'complex'
    if re.search(r'\b(commit|push|test|tests)\s*[,.]?\s*$', task_lower) or match(r'\bcommit.*(push|et push)'):
        estimated += 15

    # Decision
    if estimated <= 30:
        rec = 'execute_direct'
    elif estimated <= 120:
        rec = 'execute_direct' if complexity <= 1 else 'spawn'
    else:
        rec = 'spawn'

    model = model_name = ''
    timeout = 10
    cost = 'low'
    if rec == 'spawn':
        if complexity >= 3:
            model, model_name, cost = 'anthropic/claude-opus-4-6', 'Opus', 'high'
            timeout = min(estimated * 3, 1800)
        else:
            model, model_name, cost = 'anthropic/claude-sonnet-4-5', 'Sonnet', 'medium'
            timeout = min(estimated * 3, 600)

    reasoning = f"category={dominant} time={estimated}s complexity={complexity_name} → {rec}"
    if model_name:
        reasoning += f" ({model_name})"

    # Protection mode
    protection_file = os.environ.get('OPENCLAW_WORKSPACE', os.path.expanduser('~/.openclaw/workspace')) + '/memory/claude-usage-state.json'
    protection = os.environ.get('PROTECTION_MODE', 'false') == 'true'
    prot_override = False
    if not protection and os.path.isfile(protection_file):
        try:
            with open(protection_file) as f:
                protection = json.load(f).get('protection_mode', False)
        except Exception:
            pass

    if protection and model_name == 'Opus':
        model, model_name, cost = 'anthropic/claude-sonnet-4-5', 'Sonnet', 'medium'
        prot_override = True
        reasoning += ' ⚠️ Protection→Sonnet'

    # Check protection output
    if args.check_protection:
        if args.json_output:
            print(json.dumps({'protection_mode_active': bool(protection)}))
        else:
            print('🛡️  Protection mode: ACTIVE' if protection else '✅ Protection mode: INACTIVE')

    # Label
    label = re.sub(r'[^a-z0-9 ]', '', task_lower).split()[:4]
    label = '-'.join(label)[:40]

    # Command
    cmd = ''
    if rec == 'spawn':
        if use_notify:
            cmd = f"spawn-notify.sh --task '{task}' --model '{model}' --label '{label}' --timeout {timeout}"
        else:
            cmd = f"sessions_spawn --task '{task}' --model '{model}' --label '{label}'"

    # Output
    if args.json_output:
        print(json.dumps({
            'recommendation': rec, 'model': model, 'model_name': model_name,
            'reasoning': reasoning, 'command': cmd, 'timeout_seconds': timeout,
            'estimated_seconds': estimated, 'estimated_cost': cost,
            'complexity': complexity_name, 'category': dominant,
            'protection_mode': bool(protection), 'protection_mode_override': prot_override,
            'label': label, 'dry_run': args.dry_run,
        }, ensure_ascii=False))
    else:
        print()
        if rec == 'execute_direct':
            print(f"⚡ EXECUTE DIRECTLY (estimated {estimated}s)")
        else:
            print(f"🔀 SPAWN SUB-AGENT (estimated {estimated}s)")
        print(f"  Task:       {task}")
        print(f"  Category:   {dominant}")
        print(f"  Complexity: {complexity_name} ({complexity}/3)")
        print(f"  Model:      {model_name or 'N/A'} {'(' + model + ')' if model else ''}")
        print(f"  Timeout:    {timeout}s")
        print(f"  Cost:       {cost}")
        print(f"  Label:      {label}")
        print(f"  Reasoning:  {reasoning}")
        if cmd:
            print(f"  Command:    {cmd}")
        if protection:
            print("  🛡️  Protection ACTIVE")
        if args.dry_run:
            print("  🧪 DRY RUN")
        print()

if __name__ == '__main__':
    main()
