<?php

namespace MyStandard\Sniffs\Classes;

use PHP_CodeSniffer\Sniffs\Sniff;
use PHP_CodeSniffer\Files\File;

class ClassNamingSniff implements Sniff
{
    public function register()
    {
        return [T_CLASS];
    }

    public function process(File $phpcsFile, $stackPtr)
    {
        $tokens = $phpcsFile->getTokens();
        $className = $phpcsFile->findNext(T_STRING, $stackPtr);

        if ($className !== false) {
            $name = $tokens[$className]['content'];
            if (strtoupper($name[0]) !== $name[0]) {
                $error = 'Имя класса должно начинаться с заглавной буквы';
                $phpcsFile->addError($error, $className, 'ClassNaming');
            }
        }
    }
}
