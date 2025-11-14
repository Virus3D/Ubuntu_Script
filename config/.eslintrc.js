module.exports = {
    env: {
        browser: true,
        es2021: true,
        node: true
    },
    extends: 'eslint:recommended',
    parserOptions: {
        ecmaVersion: 12,
        sourceType: 'module'
    },
    rules: {
        'no-unused-vars': 'error',
        'prefer-const': 'error',
        'no-console': 'warn'
    },
    globals: {
        jQuery: 'readonly',
        $: 'readonly'
    }
};
