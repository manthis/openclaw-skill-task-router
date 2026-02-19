#!/usr/bin/env python3
"""task-router.py — Structural complexity × estimated time routing.

NO keyword dictionaries. NO regex. NO pattern matching.
Pure structural analysis:
  1. Word count / text length
  2. Grammatical structure (splits, punctuation)
  3. Semantic context from sentence shape

Matrix:
  < 30s           → execute_direct
  ≥ 30s + normal  → spawn Sonnet
  ≥ 30s + complex → spawn Opus
"""

import argparse
import json
import os
import sys
import unicodedata


def strip_accents(s):
    return ''.join(c for c in unicodedata.normalize('NFD', s) if unicodedata.category(c) != 'Mn')


def count_sentences(text):
    """Count sentences by splitting on sentence-ending punctuation."""
    count = 0
    for c in text:
        if c in '.!;':
            count += 1
    # A text without any terminator is still 1 sentence
    return max(count, 1)


def count_list_items(text):
    """Count numbered or bulleted list items via line-start analysis."""
    count = 0
    for line in text.split('\n'):
        stripped = line.lstrip()
        if not stripped:
            continue
        # Numbered: "1. " or "1) "
        if len(stripped) >= 3 and stripped[0].isdigit():
            rest = stripped.lstrip('0123456789')
            if rest and rest[0] in '.):' and len(rest) > 1 and rest[1] == ' ':
                count += 1
        # Bulleted: "- " or "• "
        if stripped.startswith('- ') or stripped.startswith('• '):
            count += 1
    return count


def has_technical_refs(text):
    """Detect technical references: paths, dotted identifiers, backtick code."""
    score = 0
    # Paths: contains /word/ pattern
    parts = text.split('/')
    if len(parts) >= 3:
        score += 1
    # Backtick code spans
    if text.count('`') >= 2:
        score += 1
    # Dotted identifiers (e.g. app.config.value) — 3+ segments
    for word in text.split():
        segments = word.split('.')
        if len(segments) >= 3 and all(s.isalnum() for s in segments if s):
            score += 1
            break
    # URLs
    if 'http://' in text or 'https://' in text:
        score += 1
    return score


def is_question(text, first_word_norm):
    """Detect questions from punctuation and interrogative openers."""
    if text.rstrip().endswith('?'):
        return True
    interrogatives = {
        'qui', 'que', 'quoi', 'quel', 'quelle', 'quels', 'quelles',
        'comment', 'pourquoi', 'combien', 'ou', 'quand',
        'what', 'how', 'why', 'when', 'where', 'which', 'who',
        'is', 'are', 'can', 'do', 'does', 'did', 'will', 'would',
        'could', 'should',
    }
    return first_word_norm in interrogatives


def is_trivial_message(text_lower, word_count):
    """Detect greetings, acknowledgements, emoji-only messages."""
    if word_count > 3:
        return False
    trivials = {
        'ok', 'oui', 'non', 'yes', 'no', 'merci', 'thanks', 'super', 'cool',
        'bien', 'parfait', 'good', 'great', 'nice', 'top', 'lol', 'mdr',
        'haha', 'salut', 'hello', 'hi', 'bonjour', 'bonsoir', 'hey', 'yo',
        'ciao', "d'accord", 'okay', 'go', 'yep', 'nope', 'ouais', 'yup',
        'thx', 'ty', 'np', 'gg', 'bravo', 'genial',
    }
    # Check if all words are trivial
    words = text_lower.split()
    return all(w.strip('.,!?:;') in trivials or not any(c.isalpha() for c in w) for w in words)


def count_connectors(text_norm):
    """Count multi-step connectors by checking word sequences."""
    connectors_single = {'puis', 'ensuite', 'then', 'additionally', 'furthermore', 'egalement'}
    connectors_double = {
        ('et', 'puis'), ('and', 'then'), ('after', 'that'),
        ('apres', 'ca'), ('step', 'by'),
    }
    words = text_norm.split()
    count = 0
    for w in words:
        if w in connectors_single:
            count += 1
    for i in range(len(words) - 1):
        if (words[i], words[i + 1]) in connectors_double:
            count += 1
    return count


def count_conditionals(text_norm):
    """Count conditional/constraint clauses."""
    cond_words = {'si', 'if', 'sauf', 'except', 'unless', 'selon', 'depending', 'provided'}
    words = text_norm.split()
    return sum(1 for w in words if w in cond_words)


def detect_imperative(first_word_norm, question, word_count):
    """Detect imperative sentences (commands starting with a verb)."""
    if question:
        return False
    
    # Allow 2-word commands (e.g., "debug endpoint", "crée API")
    if word_count < 2:
        return False
    
    non_action = {
        'le', 'la', 'les', 'un', 'une', 'des', 'mon', 'ma', 'mes', 'ton', 'ta', 'tes',
        'son', 'sa', 'ses', 'ce', 'cette', 'ces', 'the', 'a', 'an', 'my', 'your', 'his',
        'her', 'its', 'our', 'their', 'this', 'that', 'these', 'those',
        'je', 'tu', 'il', 'elle', 'on', 'nous', 'vous', 'ils', 'elles',
        'i', 'you', 'he', 'she', 'we', 'they', 'it',
        'ok', 'oui', 'non', 'yes', 'no', 'merci', 'thanks', 'super', 'cool', 'bien',
        'parfait', 'good', 'great', 'nice', 'top', 'salut', 'hello', 'hi',
        'bonjour', 'bonsoir', 'hey', 'yo', 'ciao',
    }
    return first_word_norm not in non_action


def is_communication_verb(first_word_norm, text_norm):
    """Detect if imperative is a communication verb (fast) vs action verb (slow).
    
    Communication verbs: announce, tell, show, display, explain, present
    Action verbs: create, build, develop, implement, deploy, install
    
    Context matters: "annoncer les résultats" (communication) vs "créer les résultats" (action)
    """
    # Communication verbs (fast, conversational)
    comm_verbs = {
        'annoncer', 'annonce', 'dire', 'dis', 'montrer', 'montre',
        'afficher', 'affiche', 'expliquer', 'explique', 'presenter', 'presente',
        'tell', 'show', 'display', 'announce', 'present', 'explain',
        'rappeler', 'rappelle', 'indiquer', 'indique', 'signaler', 'signale',
        'informer', 'informe', 'notify', 'inform', 'remind',
    }
    
    # Action verbs (slow, production)
    action_verbs = {
        'creer', 'cree', 'construire', 'construis', 'developper', 'developpe',
        'implementer', 'implemente', 'deployer', 'deploie', 'installer', 'installe',
        'create', 'build', 'develop', 'implement', 'deploy', 'install',
        'configurer', 'configure', 'setup', 'initialiser', 'initialise',
    }
    
    # Check verb type
    is_comm = first_word_norm in comm_verbs
    is_action = first_word_norm in action_verbs
    
    # If not explicitly in lists, check context
    if not is_comm and not is_action:
        return False  # Unknown verb, treat as action (conservative)
    
    # If communication verb, check object context
    if is_comm:
        # Communication objects (info, results, status) → fast
        comm_objects = {
            'resultat', 'resultats', 'info', 'infos', 'information', 'informations',
            'status', 'statut', 'etat', 'message', 'messages', 'nouvelle', 'nouvelles',
            'update', 'updates', 'summary', 'resume', 'rapport', 'report',
            'result', 'results', 'data', 'donnees', 'news',
        }
        
        # Check if any comm object appears in text
        for obj in comm_objects:
            if obj in text_norm:
                return True
        
        # Action objects (code, service, system) → slow even with comm verb
        action_objects = {
            'code', 'service', 'services', 'systeme', 'system', 'infrastructure',
            'api', 'endpoint', 'database', 'server', 'serveur', 'application',
            'app', 'fonction', 'function', 'module', 'component', 'composant',
        }
        
        for obj in action_objects:
            if obj in text_norm:
                return False
        
        # Default: communication verb without clear context → assume communication
        return True
    
    # Action verb → definitely not communication
    return False


def is_short_confirmation(text_norm, word_count, first_word_norm):
    """Detect short conversational confirmations/corrections.
    
    Pattern: Short message (≤ 10 words) starting with affirmation/negation
    Examples:
        - "Non c'était bien le spawn sonnet" → True (confirmation)
        - "Oui c'est le bon routage" → True (confirmation)
        - "Exactement ça marche bien" → True (confirmation)
        - "Non déploie avec Sonnet" → False (action with imperative)
    
    Even if technical terms appear, if it starts with yes/no and is short,
    it's likely a conversational reference, not a technical action.
    """
    if word_count > 10:
        return False
    
    # Affirmation/negation openers
    confirmation_starters = {
        'non', 'oui', 'si', 'yes', 'no', 'yeah', 'nope', 'yep',
        'exactement', 'exactly', 'tout', 'pas', 'absolument', 'absolutely',
        'indeed', 'correct', 'indeed', 'right', 'wrong', 'faux', 'vrai',
        'true', 'false',
    }
    
    if first_word_norm not in confirmation_starters:
        return False
    
    # Check for action verbs that would make it a command, not confirmation
    # Split into words and check second/third word
    words = text_norm.split()
    if len(words) < 2:
        return True  # Just "yes" or "no" alone
    
    # Action verbs that indicate a command, not a confirmation
    action_verbs = {
        'deploie', 'deploy', 'lance', 'run', 'execute', 'cree', 'create',
        'fais', 'do', 'make', 'installe', 'install', 'configure', 'setup',
        'supprime', 'delete', 'remove', 'modifie', 'modify', 'change',
        'corrige', 'fix', 'debug', 'teste', 'test', 'verifie', 'check',
    }
    
    # Check if any word (except first) is an action verb
    for word in words[1:]:
        if word in action_verbs:
            return False  # It's a command like "Non déploie avec X"
    
    # It's a confirmation/correction
    return True


def is_ambiguous_task(analysis):
    """Detect ambiguous tasks that need user clarification.
    
    Criteria:
    1. Estimated time >= 30s (needs spawn)
    2. Very short (< 5 words)
    3. Imperative (action request)
    4. Lack of structural detail (no tech refs, lists, conditionals)
    5. No clear quantifiers or targets
    """
    if analysis['estimated_seconds'] < 30:
        return False
    
    if analysis['word_count'] >= 5:
        return False
    
    if not analysis['is_imperative']:
        return False
    
    text = analysis.get('text', '')
    
    # Check for clear quantifiers or targets (indicates specific task scope)
    has_quantifier = any(c.isdigit() for c in text)  # Numbers like "10 articles"
    
    # Check for lack of structural context
    has_context = (
        analysis['technical_refs'] > 0 or
        analysis['total_steps'] > 1 or
        has_quantifier or
        '.' in text  # File extensions
    )
    
    return not has_context


def analyze_task(task: str) -> dict:
    """Analyze task purely from structural signals. No regex."""
    text = task.strip()
    text_lower = text.lower()
    text_norm = strip_accents(text_lower)
    words = text.split()
    word_count = len(words)

    first_word_norm = strip_accents(words[0].lower().rstrip('.,!?:;')) if words else ''

    question = is_question(text, first_word_norm)
    trivial = is_trivial_message(text_norm, word_count)
    imperative = detect_imperative(first_word_norm, question, word_count)
    communication = is_communication_verb(first_word_norm, text_norm) if imperative else False
    connectors = count_connectors(text_norm)
    list_items = count_list_items(text)
    sentences = count_sentences(text)
    conditionals = count_conditionals(text_norm)
    tech_refs = has_technical_refs(text)
    comma_count = text.count(',')

    total_steps = 1 + connectors + list_items
    if comma_count >= 3:
        total_steps += 1
    if sentences >= 3:
        total_steps += 1

    # ── Complexity (1=simple, 2=normal, 3=complex) ──
    complexity = 1

    if word_count > 30:
        complexity = max(complexity, 3)
    elif word_count > 15:
        complexity = max(complexity, 2)
    elif word_count > 8:
        complexity = max(complexity, 2)

    if total_steps >= 3:
        complexity = max(complexity, 3)
    elif total_steps >= 2:
        complexity = max(complexity, 2)

    if conditionals >= 2:
        complexity = max(complexity, 3)
    elif conditionals >= 1:
        complexity = max(complexity, 2)

    if tech_refs >= 2:
        complexity = max(complexity, 3)
    elif tech_refs >= 1:
        complexity = max(complexity, 2)

    # Questions cap complexity down
    if question and word_count <= 10:
        complexity = min(complexity, 1)
    elif question and word_count <= 20:
        complexity = min(complexity, 2)

    # Trivial or very short → simple
    if trivial or word_count <= 2:
        complexity = 1
    elif word_count <= 4 and not imperative:
        complexity = 1

    # ── Time estimation ──
    # Check for short confirmations FIRST (before other checks)
    is_confirmation = is_short_confirmation(text_norm, word_count, first_word_norm)
    
    if is_confirmation:
        # Short conversational confirmation/correction → fast response
        estimated = 5
    elif trivial:
        estimated = 5
    elif word_count <= 2 and not imperative:
        estimated = 5
    elif word_count <= 2 and imperative:
        # Short imperative: communication (fast) vs action (slow)
        estimated = 10 if communication else 50
    elif word_count <= 4 and not imperative:
        estimated = 10
    elif word_count <= 4 and imperative:
        # Communication verb (announce results, tell me, show status) → fast
        # Action verb (create API, deploy service, build system) → slow
        estimated = 15 if communication else 50
    elif question and word_count <= 10:
        estimated = 15
    elif question and word_count <= 20:
        estimated = 30
    elif question:
        estimated = 45
    elif word_count <= 8:
        # Still check for communication verbs in longer sentences
        estimated = 20 if communication else 35
    elif word_count <= 15:
        estimated = 30 if communication else 60
    else:
        estimated = 45 if communication else 90

    # Adjustments
    estimated += connectors * 25
    estimated += list_items * 20
    estimated += conditionals * 15
    estimated += tech_refs * 15

    if word_count > 30:
        estimated += 40

    # Question cap
    if question and word_count <= 10:
        estimated = min(estimated, 20)

    complexity_name = {1: 'simple', 2: 'normal', 3: 'complex'}[complexity]

    return {
        'estimated_seconds': estimated,
        'complexity': complexity,
        'complexity_name': complexity_name,
        'word_count': word_count,
        'is_question': question,
        'is_imperative': imperative,
        'is_communication': communication,
        'is_confirmation': is_confirmation,
        'total_steps': total_steps,
        'technical_refs': tech_refs,
        'text': text,
    }


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

    analysis = analyze_task(task)
    estimated = analysis['estimated_seconds']
    complexity = analysis['complexity']
    complexity_name = analysis['complexity_name']

    # Decision
    rec = 'execute_direct' if estimated <= 30 else 'spawn'

    # Check for ambiguous tasks that need user clarification
    uncertainty_reason = ''
    ask_user_options = {}
    
    if rec == 'spawn' and is_ambiguous_task(analysis):
        rec = 'ask_user'
        uncertainty_reason = "Demande courte et ambiguë - contexte insuffisant"
        ask_user_options = {
            'sonnet': 'Tâche standard/normale',
            'opus': 'Tâche complexe (code/debug/architecture)'
        }

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

    reasoning = (
        f"words={analysis['word_count']} steps={analysis['total_steps']} "
        f"question={analysis['is_question']} imperative={analysis['is_imperative']} "
        f"communication={analysis['is_communication']} confirmation={analysis['is_confirmation']} "
        f"tech_refs={analysis['technical_refs']} "
        f"→ time={estimated}s complexity={complexity_name} → {rec}"
    )
    if model_name:
        reasoning += f" ({model_name})"

    # Protection mode
    ws = os.environ.get('OPENCLAW_WORKSPACE', os.path.expanduser('~/.openclaw/workspace'))
    protection_file = ws + '/memory/claude-usage-state.json'
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

    if args.check_protection:
        if args.json_output:
            print(json.dumps({'protection_mode_active': bool(protection)}))
        else:
            print('🛡️  Protection mode: ACTIVE' if protection else '✅ Protection mode: INACTIVE')

    # Label
    label_words = []
    for w in task.lower().split()[:4]:
        cleaned = ''.join(c for c in w if c.isalnum() or c == ' ')
        if cleaned:
            label_words.append(cleaned)
    label = '-'.join(label_words)[:40]

    # Command
    cmd = ''
    if rec == 'spawn':
        if use_notify:
            cmd = f"spawn-notify.sh --task '{task}' --model '{model}' --label '{label}' --timeout {timeout}"
        else:
            cmd = f"sessions_spawn --task '{task}' --model '{model}' --label '{label}'"

    # Output
    if args.json_output:
        output = {
            'recommendation': rec, 'model': model, 'model_name': model_name,
            'reasoning': reasoning, 'command': cmd, 'timeout_seconds': timeout,
            'estimated_seconds': estimated, 'estimated_cost': cost,
            'complexity': complexity_name,
            'protection_mode': bool(protection), 'protection_mode_override': prot_override,
            'label': label, 'dry_run': args.dry_run,
        }
        
        # Add ask_user specific fields
        if rec == 'ask_user':
            output['uncertainty_reason'] = uncertainty_reason
            output['options'] = ask_user_options
            output['task_summary'] = task
        
        print(json.dumps(output, ensure_ascii=False))
    else:
        print()
        if rec == 'execute_direct':
            print(f"⚡ EXECUTE DIRECTLY (estimated {estimated}s)")
        elif rec == 'ask_user':
            print(f"❓ ASK USER - AMBIGUOUS TASK (estimated {estimated}s)")
            print(f"  Reason:     {uncertainty_reason}")
            print(f"  Options:")
            for model_choice, description in ask_user_options.items():
                print(f"    - {model_choice}: {description}")
        else:
            print(f"🔀 SPAWN SUB-AGENT (estimated {estimated}s)")
        print(f"  Task:       {task}")
        print(f"  Complexity: {complexity_name} ({complexity}/3)")
        if rec != 'ask_user':
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
