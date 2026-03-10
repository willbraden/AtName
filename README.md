# AtName

A WoW Classic Era addon that simulates a focus target using named macros.

Classic Era has no native focus target system. AtName works around this by generating macros that use the `[@PlayerName,exists]` conditional — so your spells cast on a specific player if they're present, and fall back to your current target if not.

## Usage

Type `/atname` or `/an` to open the panel.

## Workflow

### Setting up a macro template

1. Enter a **Focus** name, or click **From Target** to use your current target
2. Enter a short **Name** for the macro (becomes `AN_YourName`, max 13 chars)
3. Write the **Body** using `{focus}` as a placeholder for the player name
4. Click **Make Macro** — the macro is created in your macro book and saved to the template list

**Example body:**
```
#showtooltip
/cast [@{focus},exists] Blessing of Protection; Blessing of Protection
```

This generates:
```
#showtooltip
/cast [@Epicwarrior,exists] Blessing of Protection; Blessing of Protection
```

If `Epicwarrior` is in your raid, the spell targets them. If not, it falls back to your current target.

### Template list

Every macro you create is saved as a template. From the list you can:

| Button | Action |
|--------|--------|
| Click row | Load template into the form |
| **@** | Retarget this macro to your current target instantly |
| **G** | Attach macro to your cursor — click any action bar slot to place it |
| **x** | Remove from saved list |

### Retargeting

To swap a macro to a different player mid-raid:
- Target the new player → click **@** on that row

No need to open the form or retype anything. The macro updates immediately.

## Slash commands

| Command | Action |
|---------|--------|
| `/atname` | Toggle the panel |
| `/an` | Toggle the panel (shorthand) |

## Notes

- Macros are saved globally (account-wide macro slots), not per-character
- The macro name limit is 16 characters; `AN_` is prepended automatically, leaving 13 characters for your name
- WoW Classic caps you at 120 global macros
- The `{focus}` placeholder can appear anywhere in the body — multiple times if needed
