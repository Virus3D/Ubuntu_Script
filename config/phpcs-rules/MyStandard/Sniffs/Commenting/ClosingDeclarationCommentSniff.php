<?php

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
    public function register()
    {
        return [
            T_CLASS,
            T_ENUM,
            T_FUNCTION,
            T_INTERFACE,
            T_TRAIT,
        ];
    }

    /**
     * Processes this test, when one of its tokens is encountered.
     *
     * @param File $phpcsFile The file being scanned.
     * @param int  $stackPtr  The position of the current token in the
     *                        stack passed in $tokens..
     *
     * @return void
     */
    public function process(File $phpcsFile, int $stackPtr)
    {
        $tokens = $phpcsFile->getTokens();

        if ($tokens[$stackPtr]['code'] === T_FUNCTION) {
            $methodProps = $phpcsFile->getMethodProperties($stackPtr);

            // Abstract methods do not require a closing comment.
            if ($methodProps['is_abstract'] === true) {
                return;
            }

            // If this function is in an interface then we don't require
            // a closing comment.
            if ($phpcsFile->hasCondition($stackPtr, T_INTERFACE) === true) {
                return;
            }

            if (isset($tokens[$stackPtr]['scope_closer']) === false) {
                // Parse error or live coding.
                return;
            }

            $decName = $phpcsFile->getDeclarationName($stackPtr);
            if ($decName === '') {
                // Parse error or live coding.
                return;
            }

            $comment = '//end ' . $decName . '()';
        } elseif ($tokens[$stackPtr]['code'] === T_CLASS) {
            $comment = '//end class';
        } elseif ($tokens[$stackPtr]['code'] === T_INTERFACE) {
            $comment = '//end interface';
        } elseif ($tokens[$stackPtr]['code'] === T_TRAIT) {
            $comment = '//end trait';
        } else {
            $comment = '//end enum';
        }

        if (isset($tokens[$stackPtr]['scope_closer']) === false) {
            // Parse error or live coding.
            return;
        }

        $closingBracket = $tokens[$stackPtr]['scope_closer'];
        $data = [$comment];

        // Check if there's a comment after the closing brace
        $nextToken = $phpcsFile->findNext(T_WHITESPACE, ($closingBracket + 1), null, true);

        if ($nextToken === false || $tokens[$nextToken]['code'] !== T_COMMENT) {
            // No comment found - add one with space
            $fix = $phpcsFile->addFixableError('Expected %s after closing brace', $closingBracket, 'Missing', $data);
            if ($fix === true) {
                $phpcsFile->fixer->beginChangeset();
                $phpcsFile->fixer->addContent($closingBracket, ' ' . $comment);
                $phpcsFile->fixer->endChangeset();
            }
            return;
        }

        // Check if the comment is correct and has proper spacing
        $expectedComment = $comment;
        $actualComment = rtrim($tokens[$nextToken]['content']);

        // Check the spacing between } and comment
        $spaceBetween = '';
        for ($i = $closingBracket + 1; $i < $nextToken; $i++) {
            $spaceBetween .= $tokens[$i]['content'];
        }

        $hasCorrectSpacing = ($spaceBetween === ' ');
        $hasCorrectComment = ($actualComment === $expectedComment);

        if (!$hasCorrectSpacing || !$hasCorrectComment) {
            $fix = $phpcsFile->addFixableError('Expected "%s" with single space after closing brace', $closingBracket, 'Incorrect', $data);

            if ($fix === true) {
                $phpcsFile->fixer->beginChangeset();

                // Remove everything between } and comment
                for ($i = $closingBracket + 1; $i < $nextToken; $i++) {
                    $phpcsFile->fixer->replaceToken($i, '');
                }

                // Replace the comment itself
                $phpcsFile->fixer->replaceToken($nextToken, ' ' . $expectedComment);

                $phpcsFile->fixer->endChangeset();
            }
        }
    }
}
