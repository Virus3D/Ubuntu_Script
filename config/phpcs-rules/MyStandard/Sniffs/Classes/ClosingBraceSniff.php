<?php

namespace MyStandard\Sniffs\Classes;

use PHP_CodeSniffer\Sniffs\Sniff;
use PHP_CodeSniffer\Files\File;

class ClosingBraceSniff implements Sniff
{
    public function register()
    {
        return [T_CLOSE_CURLY_BRACKET];
    }

    public function process(File $phpcsFile, $stackPtr)
    {
        $tokens = $phpcsFile->getTokens();

        // Проверить, что } принадлежит методу
        $methodPtr = $phpcsFile->findPrevious(T_FUNCTION, $stackPtr);
        if (!$methodPtr) {
            return; // Если это не метод — пропустить
        }

        // Проверить, что } принадлежит именно этому методу
        $methodOpenBrace = $phpcsFile->findNext(T_OPEN_CURLY_BRACKET, $methodPtr + 1);
        $methodCloseBrace = $tokens[$methodOpenBrace]['scope_closer'] ?? false;

        if ($stackPtr !== $methodCloseBrace) {
            return; // Скобка принадлежит другой структуре
        }

        // Найти конец текущей строки (до \n или конца файла)
        $endOfLine = $phpcsFile->findNext([T_WHITESPACE, T_COMMENT], $stackPtr + 1, null, false, "\n");
        // Найти первый не пробельный токен после }
        $nextToken = $phpcsFile->findNext([T_WHITESPACE], $stackPtr + 1, $endOfLine ?: null, true);

        // Если после } ничего нет — разрешить
        if ($nextToken === false) {
            $phpcsFile->addError(
                'После закрывающей скобки метода должен быть комментарий //'." $stackPtr - $endOfLine ",
                $stackPtr,
                'MissingMethodClosingBraceComment'
            );
            return;
        }

        // Если после } есть комментарий `//` — разрешить
        if ($tokens[$nextToken]['code'] === T_COMMENT && strpos($tokens[$nextToken]['content'], '//') === 0) {
            return;
        }

        $phpcsFile->addError(
            'После закрывающей скобки метода разрешен только комментарий //',
            $stackPtr,
            'StatementAfter'
        );
    }
}
