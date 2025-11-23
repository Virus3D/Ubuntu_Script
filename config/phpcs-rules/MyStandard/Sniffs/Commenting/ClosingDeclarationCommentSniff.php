<?php

declare(strict_types=1);

namespace MyStandard\Sniffs\Commenting;

use PHP_CodeSniffer\Files\File;
use PHP_CodeSniffer\Sniffs\Sniff;

class ClosingDeclarationCommentSniff implements Sniff
{
    /**
     * Returns an array of tokens this test wants to listen for.
     *
     * @return array<int|string>
     */
    public function register(): array
    {
        return [
            T_CLASS,
            T_ENUM,
            T_FUNCTION,
            T_INTERFACE,
            T_TRAIT,
        ];
    }//end register()

    /**
     * Processes this test, when one of its tokens is encountered.
     *
     * @param File $phpcsFile The file being scanned.
     * @param int  $stackPtr  The position of the current token in the
     *                        stack passed in $tokens..
     */
    public function process(File $phpcsFile, int $stackPtr): void
    {
        $tokens = $phpcsFile->getTokens();

        // Early return if there's no scope closer (incomplete code, interface methods, etc.)
        if (!isset($tokens[$stackPtr]['scope_closer'])) {
            return;
        }

        $closingBracket = $tokens[$stackPtr]['scope_closer'];

        // Check what type of structure we're dealing with
        if ($tokens[$stackPtr]['code'] === T_FUNCTION) {
            $methodProps = $phpcsFile->getMethodProperties($stackPtr);

            // Abstract methods do not require a closing comment.
            if ($methodProps['is_abstract'] === true) {
                return;
            }

            // If this function is in an interface then we don't require a closing comment.
            if ($phpcsFile->hasCondition($stackPtr, T_INTERFACE) === true) {
                return;
            }

            $decName = $phpcsFile->getDeclarationName($stackPtr);
            if ($decName === '') {
                // Parse error or live coding.
                return;
            }

            $comment = '// end ' . $decName . '()';
        } else if ($tokens[$stackPtr]['code'] === T_CLASS) {
            $comment = '// end class';
        } else if ($tokens[$stackPtr]['code'] === T_INTERFACE) {
            $comment = '// end interface';
        } else if ($tokens[$stackPtr]['code'] === T_TRAIT) {
            $comment = '// end trait';
        } else {
            $comment = '// end enum';
        } //end if

        $data = [$comment];
        if (isset($tokens[($closingBracket + 1)]) === false || $tokens[($closingBracket + 1)]['code'] !== T_COMMENT) {
            $next = $phpcsFile->findNext(T_WHITESPACE, ($closingBracket + 1), null, true);
            if ($next !== false && rtrim($tokens[$next]['content']) === $comment) {
                // The comment isn't really missing; it is just in the wrong place.
                $fix = $phpcsFile->addFixableError('Expected %s directly after closing brace', $closingBracket, 'Misplaced', $data);
                if ($fix === true) {
                    $phpcsFile->fixer->beginChangeset();
                    for ($i = ($closingBracket + 1); $i < $next; $i++) {
                        $phpcsFile->fixer->replaceToken($i, '');
                    }

                    // Just in case, because indentation fixes can add indents onto
                    // these comments and cause us to be unable to fix them.
                    $phpcsFile->fixer->replaceToken($next, $comment . $phpcsFile->eolChar);
                    $phpcsFile->fixer->endChangeset();
                }
            } else {
                $fix = $phpcsFile->addFixableError('Expected %s', $closingBracket, 'Missing', $data);
                if ($fix === true) {
                    $phpcsFile->fixer->replaceToken($closingBracket, '}' . $comment);
                }
            }

            return;
        } //end if

        if (rtrim($tokens[($closingBracket + 1)]['content']) !== $comment) {
            $fix = $phpcsFile->addFixableError('Expected %s', $closingBracket, 'Incorrect', $data);
            if ($fix === true) {
                $phpcsFile->fixer->replaceToken(($closingBracket + 1), $comment . $phpcsFile->eolChar);
            }

            return;
        }
    }//end process()
}//end class
