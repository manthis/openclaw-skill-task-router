package main

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
	"unicode/utf8"
)

// CLI flags
type flags struct {
	task            string
	jsonOutput      bool
	checkProtection bool
	dryRun          bool
	useNotify       bool
}

func parseFlags() flags {
	f := flags{}
	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--task":
			if i+1 < len(args) {
				f.task = args[i+1]
				i++
			}
		case "--json":
			f.jsonOutput = true
		case "--check-protection":
			f.checkProtection = true
		case "--dry-run":
			f.dryRun = true
		case "--use-notify":
			f.useNotify = true
		case "--no-notify":
			f.useNotify = false
		case "-h", "--help":
			fmt.Println(`Usage: task-router --task "description" [--json] [--check-protection] [--dry-run] [--no-notify]`)
			os.Exit(0)
		default:
			fmt.Fprintf(os.Stderr, "Unknown: %s\n", args[i])
			os.Exit(1)
		}
	}
	if f.task == "" {
		fmt.Fprintln(os.Stderr, "Error: --task required")
		os.Exit(1)
	}
	return f
}

// Precompiled regexes
var (
	// Conversation
	reConvGreeting  = compile(`^(ok|oui|non|yes|no|merci|thanks|super|cool|bien|parfait|good|great|salut|hello|hi|bonjour|bonsoir|hey|yo|ciao|d.accord|okay|vas-y|go|fais-le|lance|c.est bon|top|nice|lol|mdr|haha|👍|❤️|🙏)$`)
	reConvQuestion  = compile(`^\s*(quel |quelle |comment |pourquoi |combien |où |quand |est-ce que |what |how |why |when |where |which |who |is |are |can |do |does )`)
	reConvEndsQ     = compile(`\?$`)
	reConvOpinion   = compile(`\b(penses|think|opinion|avis|recommend|conseille|préfère|prefer|choix|choice)\b`)

	// Lookup
	reLookupVerb    = compile(`\b(check|vérifie|show|affiche|list|liste|status|état|info|get|récupère|dis-moi|tell me|regarde|look|montre)\b`)
	reLookupTool    = compile(`\b(calendar|calendrier|agenda|weather|météo|meteo|heure|time|date|aujourd.hui|today|demain|tomorrow|rappelle|remind)\b`)
	reLookupRead    = compile(`\b(read|lis|log|logs|git status|git log|git diff)\b`)

	// Search
	reSearchVerb    = compile(`\b(recherche|cherche|search|find|trouve|trouver|articles?|papers?|sources?|références?)\b`)
	reSearchDeep    = compile(`\b(investigate|explore|analyze|analyse|compare|audit|review|evaluate|évalue|benchmark|état de l.art|state of the art)\b`)
	reSearchQuant   = compile(`\b[0-9]+\s*(articles?|exemples?|sources?|liens?|links?|results?|résultats?|options?|alternatives?)\b`)

	// Content
	reContentVerb   = compile(`\b(rédige|draft|compose|write|écris|résume|summarize|summary|résumé|traduis|translate)\b`)
	reContentObj    = compile(`\b(email|mail|message|lettre|letter|article|blog|post|doc|documentation|readme|rapport|report)\b`)

	// Filemod
	reFilemodVerb   = compile(`\b(update|met à jour|modifie|modify|change|edit|édite|améliore|improve|réécris|rewrite|ajoute|add|supprime|remove|delete|rename|renomme)\b`)
	reFilemodObj    = compile(`\b(fichier|file|config|\.json|\.yaml|\.yml|\.toml|\.env|\.md|\.txt)\b`)

	// Code
	reCodeKeyword   = compile(`\b(code|script|function|fonction|implement|implémente|développe|develop|programme|program|endpoint|api|route|handler|middleware|class|module|package|library|lib)\b`)
	reCodeCreate    = compile(`\b(crée|créer|create|build|write a|écris un)\b`)
	reCodeInfra     = compile(`\b(skill|plugin|tool|bot|cli|daemon|service|worker|cron|webhook|docker|container|k8s|kubernetes)\b`)
	reCodeTest      = compile(`\b(test|tests|spec|unittest|jest|pytest|ci|cd|pipeline|lint|eslint|prettier|type.?check|e2e|integration.?test|coverage)\b`)
	reCodeRefactor  = compile(`\b(refactor[ei]?|refactorise|optimize|optimise|clean.?up|restructure)\b`)

	// Debug
	reDebugFix      = compile(`\b(fix|corrige|résous|resolve|troubleshoot|répare)\b`)
	reDebugVerb     = compile(`\b(debug|debugge|diagnose|diagnostique)\b`)
	reDebugSignal   = compile(`\b(error|erreur|bug|issue|broken|cassé|crash|fail|failed|marche pas|doesn.t work|not working|problem|problème|weird|bizarre|strange|étrange)\b`)
	reDebugTech     = compile(`\b(stack.?trace|traceback|exception|segfault|undefined|null|nan|timeout|502|500|404|403|401)\b`)

	// Architecture
	reArchKeyword   = compile(`\b(architect|architecture|design|conception|plan|planifie|stratégie|strategy|roadmap|spec|specification)\b`)
	reArchSystem    = compile(`\b(système|system|infrastructure|infra|stack|database|db|schema|migration|migrate|scale|scaling)\b`)
	reArchMulti     = compile(`\b(multi|plusieurs composants|several components|microservice|monorepo|event.?driven|pub.?sub|queue|message broker)\b`)

	// Deploy
	reDeployKeyword = compile(`\b(deploy|déploie|publish|publie|release|ship|merge|pr |pull request|push to|vercel|netlify|heroku|aws|gcp|azure)\b`)
	reDeployAction  = compile(`\b(assure.?toi|assure.?toi que|ensure|make sure|vérifie que|vérife que|check that|synchronise|sync|met à jour|update)\b`)

	// Config
	reConfigKeyword = compile(`\b(install|installe|configure|setup|set up|config|provision|bootstrap|init|initialize)\b`)
	reConfigTech    = compile(`\b(ssh|ssl|tls|cert|certificate|dns|domain|nginx|apache|proxy|firewall|port|env|environment)\b`)

	// Technical object
	reTechObject    = compile(`\b(repo|repository|github|gitlab|bitbucket|git |npm|yarn|pnpm|docker|container|image|service|daemon|server|api|endpoint|database|db|version|package|module|lib|library|branch|main|master|prod|production|staging|dev)\b`)

	// Multi-step / scope
	reMultiStep     = compile(`\b(and then|et ensuite|puis|après ça|ensuite|step.?by.?step|étape par étape)\b`)
	reMultiBatch    = compile(`\b(multiple|plusieurs|every|chaque|all|tous|toutes|each|batch|bulk)\b`)
	reCommitEnd     = compile(`\b(commit|push|test|tests)\s*[,.]?\s*$|\bcommit.*(push|et push)`)

	// Question detection
	reQuestionStart = compile(`^\s*(c.est quoi|qu.est-ce que|what is|what.s|why does|why is|pourquoi|how does|how is|comment ça|explique|explain|describe|décris)`)
	reQuestionEarly = compile(`^\s*(c.est quoi|qu.est-ce que|what is|what.s|why does|pourquoi|how |comment |explique|explain|describe|décris)`)
)

func compile(pattern string) *regexp.Regexp {
	return regexp.MustCompile(pattern)
}

func match(re *regexp.Regexp, s string) bool {
	return re.MatchString(s)
}

func wordCount(s string) int {
	return len(strings.Fields(s))
}

func countChar(s string, c byte) int {
	n := 0
	for i := 0; i < len(s); i++ {
		if s[i] == c {
			n++
		}
	}
	return n
}

func min(a, b int) int {
	if a < b { return a }
	return b
}

func max(a, b int) int {
	if a > b { return a }
	return b
}

type protectionState struct {
	ProtectionMode interface{} `json:"protection_mode"`
}

func readProtection(workspace string) bool {
	if os.Getenv("PROTECTION_MODE") == "true" {
		return true
	}
	path := workspace + "/memory/claude-usage-state.json"
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	var ps protectionState
	if err := json.Unmarshal(data, &ps); err != nil {
		return false
	}
	switch v := ps.ProtectionMode.(type) {
	case bool:
		return v
	case string:
		return v == "true"
	}
	return false
}

type output struct {
	Recommendation       string `json:"recommendation"`
	Model                string `json:"model"`
	ModelName            string `json:"model_name"`
	Reasoning            string `json:"reasoning"`
	Command              string `json:"command"`
	TimeoutSeconds       int    `json:"timeout_seconds"`
	EstimatedSeconds     int    `json:"estimated_seconds"`
	EstimatedCost        string `json:"estimated_cost"`
	Complexity           string `json:"complexity"`
	Category             string `json:"category"`
	ProtectionMode       bool   `json:"protection_mode"`
	ProtectionOverride   bool   `json:"protection_mode_override"`
	Label                string `json:"label"`
	DryRun               bool   `json:"dry_run"`
	UserMessage          string `json:"user_message"`
}

func makeLabel(taskLower string) string {
	// Keep only a-z0-9 and space
	var b strings.Builder
	for _, r := range taskLower {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == ' ' {
			b.WriteRune(r)
		}
	}
	words := strings.Fields(b.String())
	n := min(4, len(words))
	label := strings.Join(words[:n], "-")
	if utf8.RuneCountInString(label) > 40 {
		label = label[:40]
	}
	return label
}

func main() {
	f := parseFlags()

	workspace := os.Getenv("OPENCLAW_WORKSPACE")
	if workspace == "" {
		workspace = os.Getenv("HOME") + "/.openclaw/workspace"
	}

	task := f.task
	taskLower := strings.ToLower(task)
	wc := wordCount(task)

	// Pre-compute question detection
	isQuestionEarly := match(reConvEndsQ, taskLower) || match(reQuestionEarly, taskLower)

	// Category scores
	catConversation := 0
	catLookup := 0
	catSearch := 0
	catContent := 0
	catFilemod := 0
	catCode := 0
	catDebug := 0
	catArchitecture := 0
	catDeploy := 0
	catConfig := 0

	// Conversation
	if match(reConvGreeting, taskLower) { catConversation += 10 }
	if match(reConvQuestion, taskLower) { catConversation += 5 }
	if match(reConvEndsQ, taskLower)    { catConversation += 3 }
	if match(reConvOpinion, taskLower)  { catConversation += 4 }

	// Lookup
	if match(reLookupVerb, taskLower) { catLookup += 5 }
	if match(reLookupTool, taskLower) { catLookup += 6 }
	if match(reLookupRead, taskLower) { catLookup += 4 }

	// Search
	if match(reSearchVerb, taskLower)  { catSearch += 5 }
	if match(reSearchDeep, taskLower)  { catSearch += 5 }
	if match(reSearchQuant, taskLower) { catSearch += 4 }

	// Content
	if match(reContentVerb, taskLower) { catContent += 5 }
	if match(reContentObj, taskLower)  { catContent += 4 }

	// Filemod
	if match(reFilemodVerb, taskLower) { catFilemod += 5 }
	if match(reFilemodObj, taskLower)  { catFilemod += 3 }

	// Code
	if match(reCodeKeyword, taskLower)  { catCode += 6 }
	if match(reCodeCreate, taskLower) {
		if catCode > 0 {
			catCode += 4
		} else {
			catContent += 2
			catCode += 2
		}
	}
	if match(reCodeInfra, taskLower)    { catCode += 5 }
	if match(reCodeTest, taskLower)     { catCode += 6 }
	if match(reCodeRefactor, taskLower) { catCode += 7 }

	// Debug
	if match(reDebugFix, taskLower)    { catDebug += 8 }
	if match(reDebugVerb, taskLower)   { catDebug += 6 }
	if match(reDebugSignal, taskLower) { catDebug += 5 }
	if match(reDebugTech, taskLower)   { catDebug += 4 }

	// Architecture
	if match(reArchKeyword, taskLower) { catArchitecture += 7 }
	if match(reArchSystem, taskLower)  { catArchitecture += 4 }
	if match(reArchMulti, taskLower)   { catArchitecture += 5 }

	// Deploy
	if match(reDeployKeyword, taskLower) { catDeploy += 6 }
	if match(reDeployAction, taskLower)  { catDeploy += 2; catConfig += 2 }

	// Config
	if match(reConfigKeyword, taskLower) { catConfig += 5 }
	if match(reConfigTech, taskLower)    { catConfig += 4 }

	// Technical object boost
	if match(reTechObject, taskLower) {
		if catDeploy >= 2 || catConfig >= 2 {
			catDeploy += 6
			catConfig += 4
		}
	}

	// Post-processing: code vs filemod
	if catCode >= 10 && catFilemod > 0 && catFilemod < catCode {
		catFilemod /= 2
	}
	if catCode >= 6 && catDebug >= 5 {
		catArchitecture += 3
	}

	// Find dominant
	type catEntry struct {
		name  string
		score int
	}
	cats := []catEntry{
		{"conversation", catConversation},
		{"lookup", catLookup},
		{"search", catSearch},
		{"content", catContent},
		{"filemod", catFilemod},
		{"code", catCode},
		{"debug", catDebug},
		{"architecture", catArchitecture},
		{"deploy", catDeploy},
		{"config", catConfig},
	}

	dominant := "conversation"
	maxScore := catConversation
	for _, c := range cats[1:] {
		if c.score > maxScore {
			maxScore = c.score
			dominant = c.name
		}
	}
	if maxScore <= 2 {
		dominant = "conversation"
	}

	// Tie-breaking
	if dominant != "conversation" && isQuestionEarly && wc <= 6 {
		if maxScore-catConversation <= 3 {
			dominant = "conversation"
		}
	}

	// Map category → base time + complexity
	var baseTime, complexity int
	var complexityName string

	switch dominant {
	case "conversation":
		baseTime, complexity, complexityName = 10, 1, "simple"
	case "lookup":
		baseTime, complexity, complexityName = 12, 1, "simple"
	case "search":
		baseTime, complexity, complexityName = 45, 2, "normal"
	case "content":
		baseTime, complexity, complexityName = 50, 2, "normal"
	case "filemod":
		baseTime, complexity, complexityName = 40, 2, "normal"
	case "code":
		baseTime, complexity, complexityName = 80, 3, "complex"
	case "debug":
		baseTime, complexity, complexityName = 90, 3, "complex"
	case "architecture":
		baseTime, complexity, complexityName = 120, 3, "complex"
	case "deploy":
		baseTime, complexity, complexityName = 60, 2, "normal"
	case "config":
		baseTime, complexity, complexityName = 50, 2, "normal"
	}

	// Question dampener
	isQuestion := match(reConvEndsQ, taskLower) || match(reQuestionStart, taskLower)
	if isQuestion && wc <= 8 {
		if dominant == "debug" || dominant == "code" || dominant == "architecture" {
			if wc <= 5 {
				complexity, complexityName, baseTime = 1, "simple", 15
			} else {
				complexity, complexityName, baseTime = 2, "normal", 25
			}
		}
	}
	if isQuestion && wc <= 12 {
		if match(reQuestionStart, taskLower) && complexity >= 3 {
			complexity, complexityName = 2, "normal"
			if baseTime > 40 { baseTime = 40 }
		}
	}

	// Time adjustments
	estimated := baseTime
	if match(reMultiStep, taskLower) { estimated += 30 }
	if match(reMultiBatch, taskLower) { estimated += 20 }

	commaCount := countChar(task, ',')
	if commaCount >= 2 { estimated += commaCount * 10 }

	if wc > 30 {
		estimated += 40
		if complexity >= 2 { complexity, complexityName = 3, "complex" }
	} else if wc > 15 {
		estimated += 20
	} else if wc <= 4 && dominant == "conversation" {
		if estimated > 10 { estimated = 10 }
	}

	if catCode >= 3 && catDebug >= 3 {
		estimated += 30
		complexity, complexityName = 3, "complex"
	}
	if catArchitecture >= 3 && catCode >= 3 {
		estimated += 40
		complexity, complexityName = 3, "complex"
	}
	if match(reCommitEnd, taskLower) { estimated += 15 }

	// Decision matrix
	rec := "execute_direct"
	if estimated <= 30 {
		rec = "execute_direct"
	} else if estimated <= 120 {
		if complexity <= 1 { rec = "execute_direct" } else { rec = "spawn" }
	} else {
		rec = "spawn"
	}

	// Model selection
	model, modelName, cost := "", "", "low"
	timeout := 10
	if rec == "spawn" {
		if complexity >= 3 {
			model, modelName, cost = "anthropic/claude-opus-4-6", "Opus", "high"
			timeout = min(estimated*5, 1800)
		} else {
			model, modelName, cost = "anthropic/claude-sonnet-4-5", "Sonnet", "medium"
			timeout = min(estimated*3, 600)
		}
	}

	reasoning := fmt.Sprintf("category=%s time=%ds complexity=%s → %s", dominant, estimated, complexityName, rec)
	if modelName != "" {
		reasoning += fmt.Sprintf(" (%s)", modelName)
	}

	// Protection mode
	protection := readProtection(workspace)
	protOverride := false
	if protection && modelName == "Opus" {
		model, modelName, cost = "anthropic/claude-sonnet-4-5", "Sonnet", "medium"
		protOverride = true
		reasoning += " ⚠️ Protection→Sonnet"
	}

	// Check protection output
	if f.checkProtection {
		if f.jsonOutput {
			fmt.Printf(`{"protection_mode_active":%t}`+"\n", protection)
		} else {
			if protection {
				fmt.Println("🛡️  Protection mode: ACTIVE")
			} else {
				fmt.Println("✅ Protection mode: INACTIVE")
			}
		}
	}

	label := makeLabel(taskLower)

	// Command
	cmd := ""
	if rec == "spawn" {
		if f.useNotify {
			cmd = fmt.Sprintf("spawn-notify.sh --task '%s' --model '%s' --label '%s' --timeout %d", task, model, label, timeout)
		} else {
			cmd = fmt.Sprintf("sessions_spawn --task '%s' --model '%s' --label '%s'", task, model, label)
		}
	}

	// Output
	if f.jsonOutput {
		userMsg := ""
		if rec == "spawn" {
			userMsg = fmt.Sprintf("Ok, je lance un sub-agent %s pour ça (~%ds)", modelName, estimated)
		}
		out := output{
			Recommendation:     rec,
			Model:              model,
			ModelName:          modelName,
			Reasoning:          reasoning,
			Command:            cmd,
			TimeoutSeconds:     timeout,
			EstimatedSeconds:   estimated,
			EstimatedCost:      cost,
			Complexity:         complexityName,
			Category:           dominant,
			ProtectionMode:     protection,
			ProtectionOverride: protOverride,
			Label:              label,
			DryRun:             f.dryRun,
			UserMessage:        userMsg,
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetEscapeHTML(false)
		enc.Encode(out)
	} else {
		fmt.Println()
		if rec == "execute_direct" {
			fmt.Printf("⚡ EXECUTE DIRECTLY (estimated %ds)\n", estimated)
		} else {
			fmt.Printf("🔀 SPAWN SUB-AGENT (estimated %ds)\n", estimated)
		}
		fmt.Printf("  Task:       %s\n", task)
		fmt.Printf("  Category:   %s\n", dominant)
		fmt.Printf("  Complexity: %s (%d/3)\n", complexityName, complexity)
		mn := "N/A"
		if modelName != "" { mn = fmt.Sprintf("%s (%s)", modelName, model) }
		fmt.Printf("  Model:      %s\n", mn)
		fmt.Printf("  Timeout:    %ds\n", timeout)
		fmt.Printf("  Cost:       %s\n", cost)
		fmt.Printf("  Label:      %s\n", label)
		fmt.Printf("  Reasoning:  %s\n", reasoning)
		if cmd != "" { fmt.Printf("  Command:    %s\n", cmd) }
		if protection { fmt.Println("  🛡️  Protection ACTIVE") }
		if f.dryRun { fmt.Println("  🧪 DRY RUN") }
		fmt.Println()
	}
}
