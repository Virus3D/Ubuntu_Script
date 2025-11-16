<?php

/**
 * Проверяет правильность именования переменных
 */

namespace MyStandard\Sniffs\Naming;

use PHP_CodeSniffer\Sniffs\Sniff;
use PHP_CodeSniffer\Files\File;

class VariableNamingSniff implements Sniff
{
    /**
     * Регистрирует токены для обработки
     *
     * @return array<int>
     */
    public function register()
    {
        return [T_VARIABLE];
    }

    /**
     * Обрабатывает токены переменных
     *
     * @param File $phpcsFile
     * @param int  $stackPtr
     *
     * @return void
     */
    public function process(File $phpcsFile, $stackPtr)
    {
        $tokens = $phpcsFile->getTokens();
        $variableName = $tokens[$stackPtr]['content'];

        // Проверяем на соответствие правилам
        if (preg_match('/^\$(m|o)[A-Z].*/', $variableName)) {
            $error = 'Переменные должны именоваться с учетом их назначения: используйте $userModel, $userService и т.д.';
            $phpcsFile->addError($error, $stackPtr, 'InvalidVariableName');
        }

        // Проверяем camelCase для локальных переменных
        if (!$this->isCamelCase($variableName)) {
            $error = 'Имена переменных должны использовать camelCase: %s';
            $data = [$variableName];
            $phpcsFile->addError($error, $stackPtr, 'NotCamelCase', $data);
        }

        // Пример проверки для ResultContainer
        if (preg_match('/^\$resultContainer$/', $variableName)) {
            // Успешно
            return;
        }
    }

    /**
     * Проверяет camelCase формат
     *
     * @param string $variableName
     *
     * @return bool
     */
    private function isCamelCase($variableName)
    {
        // Убираем $ и проверяем формат
        $nameWithoutDollar = substr($variableName, 1);

        // Допустимые паттерны:
        // - camelCase: $myVariable
        // - с подчеркиванием в тестах: $this_is_acceptable_in_tests
        // - UPPER_CASE для констант (но они обрабатываются другим сниффом)

        return preg_match('/^[a-z][a-zA-Z0-9]*$/', $nameWithoutDollar) === 1;
    }
}
