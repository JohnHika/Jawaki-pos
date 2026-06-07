import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * GitHub Integration Service
 * Searches for and integrates GitHub skills/tools for business improvement
 */
@Injectable()
export class GithubIntegrationService {
  private readonly logger = new Logger(GithubIntegrationService.name);
  private readonly githubApiUrl = 'https://api.github.com';
  private readonly githubToken: string;

  constructor(private configService: ConfigService) {
    this.githubToken = this.configService.get<string>('GITHUB_TOKEN') || '';
  }

  /**
   * Search GitHub for business automation skills
   * Finds repositories that can help with retail business operations
   */
  async searchBusinessSkills(query: string): Promise<{
    repositories: any[],
    skills: string[],
    categories: string[]
  }> {
    try {
      // Search GitHub repositories
      const repoResponse = await fetch(
        `${this.githubApiUrl}/search/repositories?q=${encodeURIComponent(query)}&sort=stars&order=desc&per_page=10`,
        {
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'Authorization': this.githubToken ? `token ${this.githubToken}` : '',
          },
        }
      );

      if (!repoResponse.ok) {
        throw new Error(`GitHub API error: ${repoResponse.status}`);
      }

      const repoData = await repoResponse.json();
      const repositories = repoData.items || [];

      // Extract skills and categories
      const skills: string[] = [...new Set<string>(repositories.flatMap(repo => {
        const tags = [];
        if (repo.description) {
          if (repo.description.includes('POS') || repo.description.includes('point-of-sale')) tags.push('POS');
          if (repo.description.includes('inventory')) tags.push('Inventory Management');
          if (repo.description.includes('loyalty')) tags.push('Customer Loyalty');
          if (repo.description.includes('automation')) tags.push('Automation');
          if (repo.description.includes('analytics')) tags.push('Analytics');
        }
        return tags;
      }))];

      const categories: string[] = [...new Set<string>(repositories.map(repo => repo.topic || 'general'))];

      return { repositories, skills, categories };

    } catch (error) {
      this.logger.error(`GitHub search failed: ${error.message}`);
      return this.getCachedBusinessSkills(query);
    }
  }

  /**
   * Get cached business skills when API is unavailable
   * Predefined list of useful GitHub skills for retail businesses
   */
  private getCachedBusinessSkills(query: string): {
    repositories: any[],
    skills: string[],
    categories: string[]
  } {
    // Predefined list of useful GitHub repositories for retail businesses
    const repositories = [
      {
        name: 'Point-of-Sale',
        description: 'Complete POS system with inventory and sales management',
        html_url: 'https://github.com/MasterXen/Point-of-Sale',
        stargazers_count: 482,
        topics: ['pos', 'retail', 'inventory']
      },
      {
        name: 'retail-pos',
        description: 'Retail POS application with customer management',
        html_url: 'https://github.com/LeeroyMasango/retail-pos',
        stargazers_count: 215,
        topics: ['pos', 'retail', 'customer-management']
      },
      {
        name: 'inventory-management',
        description: 'Advanced inventory tracking and management system',
        html_url: 'https://github.com/topics/inventory-management',
        stargazers_count: 350,
        topics: ['inventory', 'retail', 'management']
      },
      {
        name: 'customer-loyalty',
        description: 'Customer loyalty program management system',
        html_url: 'https://github.com/topics/retail-management',
        stargazers_count: 187,
        topics: ['loyalty', 'retail', 'customer']
      }
    ];

    const skills = [
      'POS System Integration',
      'Inventory Management',
      'Customer Loyalty Programs',
      'Sales Analytics',
      'Automated Reporting',
      'Mobile Payments Integration',
      'Barcode Scanning',
      'Multi-Store Management'
    ];

    const categories = [
      'Point of Sale',
      'Inventory Management',
      'Customer Relationships',
      'Business Automation',
      'Retail Analytics'
    ];

    return { repositories, skills, categories };
  }

  /**
   * Get specific GitHub repository details
   * Fetches detailed information about a repository
   */
  async getRepositoryDetails(owner: string, repo: string): Promise<any> {
    try {
      const response = await fetch(
        `${this.githubApiUrl}/repos/${owner}/${repo}`,
        {
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'Authorization': this.githubToken ? `token ${this.githubToken}` : '',
          },
        }
      );

      if (!response.ok) {
        throw new Error(`GitHub API error: ${response.status}`);
      }

      return await response.json();

    } catch (error) {
      this.logger.error(`GitHub repo details failed: ${error.message}`);
      return null;
    }
  }

  /**
   * Search for POS-related GitHub skills
   * Specialized search for point-of-sale systems
   */
  async searchPosSkills(): Promise<{
    posSystems: any[],
    integrationSkills: string[]
  }> {
    try {
      // Search for POS systems
      const posResponse = await fetch(
        `${this.githubApiUrl}/search/repositories?q=point-of-sale+OR+pos&sort=stars&order=desc&per_page=5`,
        {
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'Authorization': this.githubToken ? `token ${this.githubToken}` : '',
          },
        }
      );

      const posData = await posResponse.json();
      const posSystems = posData.items || [];

      // Extract integration skills
      const integrationSkills = posSystems.flatMap(repo => {
        const skills = [];
        if (repo.description) {
          if (repo.description.includes('inventory')) skills.push('Inventory Integration');
          if (repo.description.includes('payment')) skills.push('Payment Gateway Integration');
          if (repo.description.includes('barcode')) skills.push('Barcode Scanning');
          if (repo.description.includes('report')) skills.push('Reporting & Analytics');
          if (repo.description.includes('multi-store')) skills.push('Multi-Store Management');
        }
        return skills;
      });

      return { posSystems, integrationSkills };

    } catch (error) {
      this.logger.error(`POS skills search failed: ${error.message}`);
      return this.getCachedPosSkills();
    }
  }

  /**
   * Get cached POS skills
   * Predefined POS integration skills
   */
  private getCachedPosSkills(): {
    posSystems: any[],
    integrationSkills: string[]
  } {
    const posSystems = [
      {
        name: 'Open Source Point of Sale',
        description: 'Complete POS system with inventory, sales, and reporting',
        html_url: 'https://opensourcepos.org/',
        stargazers_count: 850,
        topics: ['pos', 'retail', 'inventory']
      },
      {
        name: 'Point-of-Sale',
        description: 'Modern POS with barcode scanning and receipt printing',
        html_url: 'https://masterxen.github.io/point-of-sale/',
        stargazers_count: 482,
        topics: ['pos', 'retail', 'barcode']
      }
    ];

    const integrationSkills = [
      'Inventory Integration',
      'Payment Gateway Integration (M-Pesa, etc.)',
      'Barcode Scanning',
      'Reporting & Analytics',
      'Multi-Store Management',
      'Customer Loyalty Integration',
      'Tax Calculation',
      'Receipt Printing',
      'Offline Mode Support'
    ];

    return { posSystems, integrationSkills };
  }

  /**
   * Get retail automation skills from GitHub
   * Comprehensive list of automation skills for retail businesses
   */
  async getRetailAutomationSkills(): Promise<{
    automationAreas: string[],
    skillExamples: string[],
    githubResources: any[]
  }> {
    // Use cached data for now
    // In production, this would search GitHub for the latest skills
    return {
      automationAreas: [
        'Point of Sale Automation',
        'Inventory Management',
        'Customer Relationship Management',
        'Sales Analytics',
        'Loyalty Programs',
        'Supply Chain Automation',
        'Financial Reporting',
        'Employee Management'
      ],
      skillExamples: [
        'Automated stock reordering',
        'Real-time sales tracking',
        'Customer purchase history analysis',
        'Automated discount applications',
        'Loyalty points calculation',
        'Multi-channel sales integration',
        'Automated tax compliance',
        'Employee performance tracking'
      ],
      githubResources: [
        {
          name: 'Business Automation Topics',
          url: 'https://github.com/topics/business-automation',
          description: 'GitHub repositories for business automation'
        },
        {
          name: 'Retail Management Systems',
          url: 'https://github.com/topics/retail-management',
          description: 'Retail-specific management systems'
        },
        {
          name: 'POS System Repositories',
          url: 'https://repos.ecosyste.ms/hosts/GitHub/topics/pos-system',
          description: 'Point of Sale system repositories'
        }
      ]
    };
  }

  /**
   * Integrate GitHub skills with business analysis
   * Combines GitHub knowledge with AI cognitive analysis
   */
  async integrateSkillsWithAnalysis(businessType: string, location: string): Promise<{
    relevantSkills: string[],
    integrationOpportunities: string[],
    githubResources: any[]
  }> {
    // Search for relevant skills
    const searchQuery = `${businessType} automation ${location}`;
    const skillsResult = await this.searchBusinessSkills(searchQuery);

    // Get POS-specific skills
    const posResult = await this.searchPosSkills();

    // Combine and deduplicate
    const allSkills = [...new Set([...skillsResult.skills, ...posResult.integrationSkills])];

    // Identify integration opportunities
    const integrationOpportunities = allSkills.filter(skill =>
      skill.includes('Integration') || skill.includes('Automation')
    );

    // Get additional resources
    const resourcesResult = await this.getRetailAutomationSkills();

    return {
      relevantSkills: allSkills,
      integrationOpportunities,
      githubResources: resourcesResult.githubResources
    };
  }
}
