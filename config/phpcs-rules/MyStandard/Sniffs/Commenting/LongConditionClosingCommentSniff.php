<?php

namespace MyStandard\Sniffs\Commenting;

use PHP_CodeSniffer\Files\File;
use PHP_CodeSniffer\Sniffs\Sniff;

class LongConditionClosingCommentSniff implements Sniff
{

    /**
     * The condition openers that we are interested in.
     *
     * @var array<int|string, int|string>
     */
    private const CONDITION_OPENERS = [
        T_SWITCH  => T_SWITCH,
        T_IF      => T_IF,
        T_FOR     => T_FOR,
        T_FOREACH => T_FOREACH,
        T_WHILE   => T_WHILE,
        T_TRY     => T_TRY,
        T_CASE    => T_CASE,
        T_MATCH   => T_MATCH,
    ];

    /**
     * The length that a code block must be before
     * requiring a closing comment.
     *
     * @var integer
     */
    public $lineLimit = 20;

    /**
     * The format the end comment should be in.
     *
     * The placeholder %s will be replaced with the type of condition opener.
     *
     * @var string
     */
    public $commentFormat = '//end %s';


    /**
     * Returns an array of tokens this test wants to listen for.
     *
     * @return array<int|string>
     */
    public function register()
    {
        return [T_CLOSE_CURLY_BRACKET];
    }


    /**
     * Processes this test, when one of its tokens is encountered.
     *
     * @param \PHP_CodeSniffer\Files\File $phpcsFile The file being scanned.
     * @param int                         $stackPtr  The position of the current token in the
     *                                               stack passed in $tokens.
     *
     * @return void
     */
    public function process(File $phpcsFile, int $stackPtr)
    {
        $tokens = $phpcsFile->getTokens();

        if (isset($tokens[$stackPtr]['scope_condition']) === false) {
            // No scope condition. It is a function closer.
            return;
        }

        $startCondition = $tokens[$tokens[$stackPtr]['scope_condition']];
        $startBrace     = $tokens[$tokens[$stackPtr]['scope_opener']];
        $endBrace       = $tokens[$stackPtr];

        // We are only interested in some code blocks.
        if (isset(self::CONDITION_OPENERS[$startCondition['code']]) === false) {
            return;
        }

        if ($startCondition['code'] === T_IF) {
            // If this is actually an ELSE IF, skip it as the brace
            // will be checked by the original IF.
            $else = $phpcsFile->findPrevious(T_WHITESPACE, ($tokens[$stackPtr]['scope_condition'] - 1), null, true);
            if ($tokens[$else]['code'] === T_ELSE) {
                return;
            }

            // IF statements that have an ELSE block need to use
            // "end if" rather than "end else" or "end elseif".
            do {
                $nextToken = $phpcsFile->findNext(T_WHITESPACE, ($stackPtr + 1), null, true);
                if ($tokens[$nextToken]['code'] === T_ELSE || $tokens[$nextToken]['code'] === T_ELSEIF) {
                    // Check for ELSE IF (2 tokens) as opposed to ELSEIF (1 token).
                    if (
                        $tokens[$nextToken]['code'] === T_ELSE
                        && isset($tokens[$nextToken]['scope_closer']) === false
                    ) {
                        $nextToken = $phpcsFile->findNext(T_WHITESPACE, ($nextToken + 1), null, true);
                        if (
                            $tokens[$nextToken]['code'] !== T_IF
                            || isset($tokens[$nextToken]['scope_closer']) === false
                        ) {
                            // Not an ELSE IF or is an inline ELSE IF.
                            break;
                        }
                    }

                    if (isset($tokens[$nextToken]['scope_closer']) === false) {
                        // There isn't going to be anywhere to print the "end if" comment
                        // because there is no closer.
                        return;
                    }

                    // The end brace becomes the ELSE's end brace.
                    $stackPtr = $tokens[$nextToken]['scope_closer'];
                    $endBrace = $tokens[$stackPtr];
                } else {
                    break;
                }
            } while (isset($tokens[$nextToken]['scope_closer']) === true);
        }

        if ($startCondition['code'] === T_TRY) {
            // TRY statements need to check until the end of all CATCH statements.
            do {
                $nextToken = $phpcsFile->findNext(T_WHITESPACE, ($stackPtr + 1), null, true);
                if (
                    $tokens[$nextToken]['code'] === T_CATCH
                    || $tokens[$nextToken]['code'] === T_FINALLY
                ) {
                    // The end brace becomes the CATCH end brace.
                    $stackPtr = $tokens[$nextToken]['scope_closer'];
                    $endBrace = $tokens[$stackPtr];
                } else {
                    break;
                }
            } while (isset($tokens[$nextToken]['scope_closer']) === true);
        }

        if ($startCondition['code'] === T_MATCH) {
            // Move the stackPtr to after the semicolon/comma if there is one.
            $nextToken = $phpcsFile->findNext(T_WHITESPACE, ($stackPtr + 1), null, true);
            if (
                $nextToken !== false
                && ($tokens[$nextToken]['code'] === T_SEMICOLON
                    || $tokens[$nextToken]['code'] === T_COMMA)
            ) {
                $stackPtr = $nextToken;
            }
        }

        $lineDifference = ($endBrace['line'] - $startBrace['line']);

        $expected = sprintf($this->commentFormat, $startCondition['content']);
        $comment  = $phpcsFile->findNext([T_COMMENT], $stackPtr, null, false);

        if (($comment === false) || ($tokens[$comment]['line'] !== $endBrace['line'])) {
            if ($lineDifference >= $this->lineLimit) {
                $error = 'End comment for long condition not found; expected "%s"';
                $data  = [$expected];
                $fix   = $phpcsFile->addFixableError($error, $stackPtr, 'Missing', $data);

                if ($fix === true) {
                    $next = $phpcsFile->findNext(T_WHITESPACE, ($stackPtr + 1), null, true);
                    if ($next !== false && $tokens[$next]['line'] === $tokens[$stackPtr]['line']) {
                        $expected .= $phpcsFile->eolChar;
                    }

                    // MODIFIED: Add space before comment
                    $phpcsFile->fixer->addContent($stackPtr, ' ' . $expected);
                }
            }

            return;
        }

        // MODIFIED: Check for proper spacing (exactly one space)
        $spaceBetween = '';
        for ($i = $stackPtr + 1; $i < $comment; $i++) {
            $spaceBetween .= $tokens[$i]['content'];
        }

        $hasCorrectSpacing = ($spaceBetween === ' ');
        $hasCorrectComment = (trim($tokens[$comment]['content']) === $expected);

        if (!$hasCorrectSpacing || !$hasCorrectComment) {
            $error = 'Expected "%s" with single space after closing brace';
            $data  = [$expected];
            $fix = $phpcsFile->addFixableError($error, $stackPtr, 'SpacingOrComment', $data);

            if ($fix === true) {
                $phpcsFile->fixer->beginChangeset();

                // Remove everything between } and comment
                for ($i = $stackPtr + 1; $i < $comment; $i++) {
                    $phpcsFile->fixer->replaceToken($i, '');
                }

                // Replace the comment with proper spacing
                $phpcsFile->fixer->replaceToken($comment, ' ' . $expected);

                $phpcsFile->fixer->endChangeset();
            }
            return;
        }
    }
}
